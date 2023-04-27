defmodule Indexer.Fetcher.OptimismOutputRoot do
  @moduledoc """
  Fills op_output_roots DB table.
  """

  use GenServer
  use Indexer.Fetcher

  require Logger

  import Ecto.Query

  import EthereumJSONRPC, only: [quantity_to_integer: 1]

  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.OptimismOutputRoot
  alias Indexer.{BoundQueue, Helpers}
  alias Indexer.Fetcher.Optimism

  @block_check_interval_range_size 100

  # 32-byte signature of the event OutputProposed(bytes32 indexed outputRoot, uint256 indexed l2OutputIndex, uint256 indexed l2BlockNumber, uint256 l1Timestamp)
  @output_proposed_event "0xa7aaf2512769da4e444e3de247be2564225c2e7a8f74cfe528e46e17d24868e2"

  def child_spec(start_link_arguments) do
    spec = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, start_link_arguments},
      restart: :transient,
      type: :worker
    }

    Supervisor.child_spec(spec, [])
  end

  def start_link(args, gen_server_options \\ []) do
    GenServer.start_link(__MODULE__, args, Keyword.put_new(gen_server_options, :name, __MODULE__))
  end

  @impl GenServer
  def init(_args) do
    Logger.metadata(fetcher: :optimism_output_root)

    env = Application.get_all_env(:indexer)[__MODULE__]

    with {:start_block_l1_undefined, false} <- {:start_block_l1_undefined, is_nil(env[:start_block_l1])},
         optimism_l1_rpc <- Application.get_env(:indexer, :optimism_l1_rpc),
         {:rpc_l1_undefined, false} <- {:rpc_l1_undefined, is_nil(optimism_l1_rpc)},
         {:output_oracle_valid, true} <- {:output_oracle_valid, Helpers.is_address_correct?(env[:output_oracle])},
         start_block_l1 <- Optimism.parse_integer(env[:start_block_l1]),
         false <- is_nil(start_block_l1),
         true <- start_block_l1 > 0,
         {last_l1_block_number, last_l1_transaction_hash} <- get_last_l1_item(),
         {:start_block_l1_valid, true} <-
           {:start_block_l1_valid, start_block_l1 <= last_l1_block_number || last_l1_block_number == 0},
         json_rpc_named_arguments <- json_rpc_named_arguments(optimism_l1_rpc),
         {:ok, last_l1_tx} <- Optimism.get_transaction_by_hash(last_l1_transaction_hash, json_rpc_named_arguments),
         {:l1_tx_not_found, false} <- {:l1_tx_not_found, !is_nil(last_l1_transaction_hash) && is_nil(last_l1_tx)},
         {:ok, last_safe_block} <- Optimism.get_block_number_by_tag("safe", json_rpc_named_arguments),
         first_block <- max(last_safe_block - @block_check_interval_range_size, 1),
         {:ok, first_block_timestamp} <- Optimism.get_block_timestamp_by_number(first_block, json_rpc_named_arguments),
         {:ok, last_safe_block_timestamp} <-
           Optimism.get_block_timestamp_by_number(last_safe_block, json_rpc_named_arguments) do
      block_check_interval =
        ceil((last_safe_block_timestamp - first_block_timestamp) / (last_safe_block - first_block) * 1000 / 2)

      Logger.info("Block check interval is calculated as #{block_check_interval} ms.")

      start_block = max(start_block_l1, last_l1_block_number)

      reorg_monitor_task =
        Task.Supervisor.async_nolink(Indexer.Fetcher.OptimismOutputRoot.TaskSupervisor, fn ->
          reorg_monitor(block_check_interval, json_rpc_named_arguments)
        end)

      {:ok,
       %{
         output_oracle: env[:output_oracle],
         block_check_interval: block_check_interval,
         start_block: start_block,
         end_block: last_safe_block,
         reorg_monitor_task: reorg_monitor_task,
         json_rpc_named_arguments: json_rpc_named_arguments
       }, {:continue, nil}}
    else
      {:start_block_l1_undefined, true} ->
        # the process shoudln't start if the start block is not defined
        :ignore

      {:rpc_l1_undefined, true} ->
        Logger.error("L1 RPC URL is not defined.")
        :ignore

      {:output_oracle_valid, false} ->
        Logger.error("Output Oracle address is invalid or not defined.")
        :ignore

      {:start_block_l1_valid, false} ->
        Logger.error("Invalid L1 Start Block value. Please, check the value and op_output_roots table.")
        :ignore

      {:error, error_data} ->
        Logger.error(
          "Cannot get last L1 transaction from RPC by its hash, last safe block, or block timestamp by its number due to RPC error: #{inspect(error_data)}"
        )

        :ignore

      {:l1_tx_not_found, true} ->
        Logger.error(
          "Cannot find last L1 transaction from RPC by its hash. Probably, there was a reorg on L1 chain. Please, check op_output_roots table."
        )

        :ignore

      _ ->
        Logger.error("Output Roots Start Block is invalid or zero.")
        :ignore
    end
  end

  @impl GenServer
  def handle_continue(
        _,
        %{
          output_oracle: output_oracle,
          block_check_interval: block_check_interval,
          start_block: start_block,
          end_block: end_block,
          json_rpc_named_arguments: json_rpc_named_arguments
        } = state
      ) do
    # credo:disable-for-next-line
    time_before = Timex.now()

    chunks_number = ceil((end_block - start_block + 1) / Optimism.get_logs_range_size())
    chunk_range = Range.new(0, max(chunks_number - 1, 0), 1)

    last_written_block =
      chunk_range
      |> Enum.reduce_while(start_block - 1, fn current_chank, _ ->
        chunk_start = start_block + Optimism.get_logs_range_size() * current_chank
        chunk_end = min(chunk_start + Optimism.get_logs_range_size() - 1, end_block)

        if chunk_end >= chunk_start do
          Optimism.log_blocks_chunk_handling(chunk_start, chunk_end, start_block, end_block, nil, "L1")

          {:ok, result} =
            Optimism.get_logs(
              chunk_start,
              chunk_end,
              output_oracle,
              @output_proposed_event,
              json_rpc_named_arguments,
              100_000_000
            )

          output_roots = events_to_output_roots(result)

          {:ok, _} =
            Chain.import(%{
              optimism_output_roots: %{params: output_roots},
              timeout: :infinity
            })

          Optimism.log_blocks_chunk_handling(
            chunk_start,
            chunk_end,
            start_block,
            end_block,
            "#{Enum.count(output_roots)} OutputProposed event(s)",
            "L1"
          )
        end

        reorg_block = reorg_block_pop()

        if !is_nil(reorg_block) && reorg_block > 0 do
          {deleted_count, _} = Repo.delete_all(from(r in OptimismOutputRoot, where: r.l1_block_number >= ^reorg_block))

          if deleted_count > 0 do
            Logger.warning(
              "As L1 reorg was detected, all rows with l1_block_number >= #{reorg_block} were removed from the op_output_roots table. Number of removed rows: #{deleted_count}."
            )
          end

          {:halt, if(reorg_block <= chunk_end, do: reorg_block - 1, else: chunk_end)}
        else
          {:cont, chunk_end}
        end
      end)

    new_start_block = last_written_block + 1
    {:ok, new_end_block} = Optimism.get_block_number_by_tag("latest", json_rpc_named_arguments, 100_000_000)

    if new_end_block == last_written_block do
      # there is no new block, so wait for some time to let the chain issue the new block
      :timer.sleep(max(block_check_interval - Timex.diff(Timex.now(), time_before, :milliseconds), 0))
    end

    {:noreply, %{state | start_block: new_start_block, end_block: new_end_block}, {:continue, nil}}
  end

  @impl GenServer
  def handle_info({ref, _result}, %{reorg_monitor_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | reorg_monitor_task: nil}}
  end

  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %{
          reorg_monitor_task: %Task{pid: pid, ref: ref},
          block_check_interval: block_check_interval,
          json_rpc_named_arguments: json_rpc_named_arguments
        } = state
      ) do
    if reason === :normal do
      {:noreply, %{state | reorg_monitor_task: nil}}
    else
      Logger.error(fn -> "Reorgs monitor task exited due to #{inspect(reason)}. Rerunning..." end)

      task =
        Task.Supervisor.async_nolink(Indexer.Fetcher.OptimismOutputRoot.TaskSupervisor, fn ->
          reorg_monitor(block_check_interval, json_rpc_named_arguments)
        end)

      {:noreply, %{state | reorg_monitor_task: task}}
    end
  end

  defp events_to_output_roots(events) do
    Enum.map(events, fn event ->
      [l1_timestamp] = Optimism.decode_data(event["data"], [{:uint, 256}])
      {:ok, l1_timestamp} = DateTime.from_unix(l1_timestamp)

      %{
        l2_output_index: quantity_to_integer(Enum.at(event["topics"], 2)),
        l2_block_number: quantity_to_integer(Enum.at(event["topics"], 3)),
        l1_transaction_hash: event["transactionHash"],
        l1_timestamp: l1_timestamp,
        l1_block_number: quantity_to_integer(event["blockNumber"]),
        output_root: Enum.at(event["topics"], 1)
      }
    end)
  end

  defp reorg_monitor(block_check_interval, json_rpc_named_arguments) do
    Logger.metadata(fetcher: :optimism_output_root)

    # infinite loop
    # credo:disable-for-next-line
    Enum.reduce_while(Stream.iterate(0, &(&1 + 1)), 0, fn _i, prev_latest ->
      {:ok, latest} = Optimism.get_block_number_by_tag("latest", json_rpc_named_arguments, 100_000_000)

      if latest < prev_latest do
        Logger.warning("Reorg detected: previous latest block ##{prev_latest}, current latest block ##{latest}.")
        reorg_block_push(latest)
      end

      :timer.sleep(block_check_interval)

      {:cont, latest}
    end)

    :ok
  end

  defp reorg_block_pop do
    case BoundQueue.pop_front(reorg_queue_get()) do
      {:ok, {block_number, updated_queue}} ->
        :ets.insert(:op_output_roots_reorgs, {:queue, updated_queue})
        block_number

      {:error, :empty} ->
        nil
    end
  end

  defp reorg_block_push(block_number) do
    {:ok, updated_queue} = BoundQueue.push_back(reorg_queue_get(), block_number)
    :ets.insert(:op_output_roots_reorgs, {:queue, updated_queue})
  end

  defp reorg_queue_get do
    if :ets.whereis(:op_output_roots_reorgs) == :undefined do
      :ets.new(:op_output_roots_reorgs, [
        :set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    with info when info != :undefined <- :ets.info(:op_output_roots_reorgs),
         [{_, value}] <- :ets.lookup(:op_output_roots_reorgs, :queue) do
      value
    else
      _ -> %BoundQueue{}
    end
  end

  defp get_last_l1_item do
    query =
      from(root in OptimismOutputRoot,
        select: {root.l1_block_number, root.l1_transaction_hash},
        order_by: [desc: root.l2_output_index],
        limit: 1
      )

    query
    |> Repo.one()
    |> Kernel.||({0, nil})
  end

  defp json_rpc_named_arguments(optimism_l1_rpc) do
    [
      transport: EthereumJSONRPC.HTTP,
      transport_options: [
        http: EthereumJSONRPC.HTTP.HTTPoison,
        url: optimism_l1_rpc,
        http_options: [
          recv_timeout: :timer.minutes(10),
          timeout: :timer.minutes(10),
          hackney: [pool: :ethereum_jsonrpc]
        ]
      ]
    ]
  end
end
