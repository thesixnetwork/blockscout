defmodule Explorer.Chain.Import do
  @moduledoc """
  Bulk importing of data into `Explorer.Repo`
  """

  alias Ecto.Changeset
  alias Explorer.Chain.Events.Publisher
  alias Explorer.Chain.Import
  alias Explorer.Repo

  @stages [
    Import.Stage.Addresses,
    Import.Stage.AddressReferencing,
    Import.Stage.BlockReferencing,
    Import.Stage.BlockFollowing,
    Import.Stage.BlockPending
  ]

  # in order so that foreign keys are inserted before being referenced
  @runners Enum.flat_map(@stages, fn stage -> stage.runners() end)

  quoted_runner_option_value =
    quote do
      Import.Runner.options()
    end

  quoted_runner_options =
    for runner <- @runners do
      quoted_key =
        quote do
          optional(unquote(runner.option_key()))
        end

      {quoted_key, quoted_runner_option_value}
    end

  @type all_options :: %{
          optional(:broadcast) => atom,
          optional(:timeout) => timeout,
          unquote_splicing(quoted_runner_options)
        }

  quoted_runner_imported =
    for runner <- @runners do
      quoted_key =
        quote do
          optional(unquote(runner.option_key()))
        end

      quoted_value =
        quote do
          unquote(runner).imported()
        end

      {quoted_key, quoted_value}
    end

  @type all_result ::
          {:ok, %{unquote_splicing(quoted_runner_imported)}}
          | {:error, [Changeset.t()] | :timeout}
          | {:error, step :: Ecto.Multi.name(), failed_value :: any(),
             changes_so_far :: %{optional(Ecto.Multi.name()) => any()}}

  @type timestamps :: %{inserted_at: DateTime.t(), updated_at: DateTime.t()}

  # milliseconds
  @transaction_timeout :timer.minutes(4)

  @imported_table_rows @runners
                       |> Stream.map(&Map.put(&1.imported_table_row(), :key, &1.option_key()))
                       |> Enum.map_join("\n", fn %{
                                                   key: key,
                                                   value_type: value_type,
                                                   value_description: value_description
                                                 } ->
                         "| `#{inspect(key)}` | `#{value_type}` | #{value_description} |"
                       end)
  @runner_options_doc Enum.map_join(@runners, fn runner ->
                        ecto_schema_module = runner.ecto_schema_module()

                        """
                          * `#{runner.option_key() |> inspect()}`
                            * `:on_conflict` - what to do if a conflict occurs with a pre-existing row: `:nothing`, `:replace_all`, or an
                              `t:Ecto.Query.t/0` to update specific columns.
                            * `:params` - `list` of params for changeset function in `#{ecto_schema_module}`.
                            * `:with` - changeset function to use in `#{ecto_schema_module}`.  Default to `:changeset`.
                            * `:timeout` - the timeout for inserting each batch of changes from `:params`.
                              Defaults to `#{runner.timeout()}` milliseconds.
                        """
                      end)

  @doc """
  Bulk insert all data stored in the `Explorer`.

  The import returns the unique key(s) for each type of record inserted.

  | Key | Value Type | Value Description |
  |-----|------------|-------------------|
  #{@imported_table_rows}

  The params for each key are validated using the corresponding `Ecto.Schema` module's `changeset/2` function.  If there
  are errors, they are returned in `Ecto.Changeset.t`s, so that the original, invalid value can be reconstructed for any
  error messages.

  Because there are multiple processes potentially writing to the same tables at the same time,
  `c:Ecto.Repo.insert_all/2`'s
  [`:conflict_target` and `:on_conflict` options](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert_all/3-options) are
  used to perform [upserts](https://hexdocs.pm/ecto/Ecto.Repo.html#c:insert_all/3-upserts) on all tables, so that
  a pre-existing unique key will not trigger a failure, but instead replace or otherwise update the row.

  ## Data Notifications

  On successful inserts, processes interested in certain domains of data will be notified
  that new data has been inserted. See `Explorer.Chain.Events.Subscriber.to_events/2` for more information.

  ## Options

    * `:broadcast` - Boolean flag indicating whether or not to broadcast the event.
    * `:timeout` - the timeout for the whole `c:Ecto.Repo.transaction/0` call.  Defaults to `#{@transaction_timeout}`
      milliseconds.
  #{@runner_options_doc}
  """
  @spec all(all_options()) :: all_result()
  def all(options) when is_map(options) do
    with {:ok, runner_options_pairs} <- validate_options(options),
         {:ok, valid_runner_option_pairs} <- validate_runner_options_pairs(runner_options_pairs),
         {:ok, runner_to_changes_list} <- runner_to_changes_list(valid_runner_option_pairs),
         {:ok, data} <- insert_runner_to_changes_list(runner_to_changes_list, options) do
      Publisher.broadcast(data, Map.get(options, :broadcast, false))
      {:ok, data}
    end
  end

  defp runner_to_changes_list(runner_options_pairs) when is_list(runner_options_pairs) do
    runner_options_pairs
    |> Stream.map(fn {runner, options} -> runner_changes_list(runner, options) end)
    |> Enum.reduce({:ok, %{}}, fn
      {:ok, {runner, changes_list}}, {:ok, acc_runner_to_changes_list} ->
        {:ok, Map.put(acc_runner_to_changes_list, runner, changes_list)}

      {:ok, _}, {:error, _} = error ->
        error

      {:error, _} = error, {:ok, _} ->
        error

      {:error, runner_changesets}, {:error, acc_changesets} ->
        {:error, acc_changesets ++ runner_changesets}
    end)
  end

  defp runner_changes_list(runner, %{params: params} = options) do
    ecto_schema_module = runner.ecto_schema_module()
    changeset_function_name = Map.get(options, :with, :changeset)
    struct = ecto_schema_module.__struct__()

    params
    |> Stream.map(&apply(ecto_schema_module, changeset_function_name, [struct, &1]))
    |> Enum.reduce({:ok, []}, fn
      changeset = %Changeset{valid?: false}, {:ok, _} ->
        {:error, [changeset]}

      changeset = %Changeset{valid?: false}, {:error, acc_changesets} ->
        {:error, [changeset | acc_changesets]}

      %Changeset{changes: changes, valid?: true}, {:ok, acc_changes} ->
        {:ok, [changes | acc_changes]}

      %Changeset{valid?: true}, {:error, _} = error ->
        error

      :ignore, error ->
        {:error, error}
    end)
    |> case do
      {:ok, changes} -> {:ok, {runner, changes}}
      {:error, _} = error -> error
    end
  end

  @global_options ~w(broadcast timeout)a

  defp validate_options(options) when is_map(options) do
    local_options = Map.drop(options, @global_options)

    {reverse_runner_options_pairs, unknown_options} =
      Enum.reduce(@runners, {[], local_options}, fn runner, {acc_runner_options_pairs, unknown_options} = acc ->
        option_key = runner.option_key()

        case local_options do
          %{^option_key => option_value} ->
            {[{runner, option_value} | acc_runner_options_pairs], Map.delete(unknown_options, option_key)}

          _ ->
            acc
        end
      end)

    case Enum.empty?(unknown_options) do
      true -> {:ok, Enum.reverse(reverse_runner_options_pairs)}
      false -> {:error, {:unknown_options, unknown_options}}
    end
  end

  defp validate_runner_options_pairs(runner_options_pairs) when is_list(runner_options_pairs) do
    {status, reversed} =
      runner_options_pairs
      |> Stream.map(fn {runner, options} -> validate_runner_options(runner, options) end)
      |> Enum.reduce({:ok, []}, fn
        :ignore, acc ->
          acc

        {:ok, valid_runner_option_pair}, {:ok, valid_runner_options_pairs} ->
          {:ok, [valid_runner_option_pair | valid_runner_options_pairs]}

        {:ok, _}, {:error, _} = error ->
          error

        {:error, reason}, {:ok, _} ->
          {:error, [reason]}

        {:error, reason}, {:error, reasons} ->
          {:error, [reason | reasons]}
      end)

    {status, Enum.reverse(reversed)}
  end

  defp validate_runner_options(runner, options) when is_map(options) do
    option_key = runner.option_key()

    runner_specific_options =
      if Map.has_key?(Enum.into(runner.__info__(:functions), %{}), :runner_specific_options) do
        apply(runner, :runner_specific_options, [])
      else
        []
      end

    case {validate_runner_option_params_required(option_key, options),
          validate_runner_options_known(option_key, options, runner_specific_options)} do
      {:ignore, :ok} -> :ignore
      {:ignore, {:error, _} = error} -> error
      {:ok, :ok} -> {:ok, {runner, options}}
      {:ok, {:error, _} = error} -> error
      {{:error, reason}, :ok} -> {:error, [reason]}
      {{:error, reason}, {:error, reasons}} -> {:error, [reason | reasons]}
    end
  end

  defp validate_runner_option_params_required(_, %{params: params}) do
    case Enum.empty?(params) do
      false -> :ok
      true -> :ignore
    end
  end

  defp validate_runner_option_params_required(runner_option_key, _),
    do: {:error, {:required, [runner_option_key, :params]}}

  @local_options ~w(on_conflict params with timeout)a

  defp validate_runner_options_known(runner_option_key, options, runner_specific_options) do
    base_unknown_option_keys = Map.keys(options) -- @local_options
    unknown_option_keys = base_unknown_option_keys -- runner_specific_options

    if Enum.empty?(unknown_option_keys) do
      :ok
    else
      reasons = Enum.map(unknown_option_keys, &{:unknown, [runner_option_key, &1]})

      {:error, reasons}
    end
  end

  defp runner_to_changes_list_to_multis(runner_to_changes_list, options)
       when is_map(runner_to_changes_list) and is_map(options) do
    timestamps = timestamps()
    full_options = Map.put(options, :timestamps, timestamps)

    {multis, final_runner_to_changes_list} =
      Enum.flat_map_reduce(@stages, runner_to_changes_list, fn stage, remaining_runner_to_changes_list ->
        stage.multis(remaining_runner_to_changes_list, full_options)
      end)

    unless Enum.empty?(final_runner_to_changes_list) do
      raise ArgumentError,
            "No stages consumed the following runners: #{final_runner_to_changes_list |> Map.keys() |> inspect()}"
    end

    multis
  end

  def insert_changes_list(repo, changes_list, options) when is_atom(repo) and is_list(changes_list) do
    ecto_schema_module = Keyword.fetch!(options, :for)

    timestamped_changes_list = timestamp_changes_list(changes_list, Keyword.fetch!(options, :timestamps))

    {_, inserted} =
      repo.safe_insert_all(
        ecto_schema_module,
        timestamped_changes_list,
        Keyword.delete(options, :for)
      )

    {:ok, inserted}
  end

  defp timestamp_changes_list(changes_list, timestamps) when is_list(changes_list) do
    Enum.map(changes_list, &timestamp_params(&1, timestamps))
  end

  defp timestamp_params(changes, timestamps) when is_map(changes) do
    Map.merge(changes, timestamps)
  end

  defp insert_runner_to_changes_list(runner_to_changes_list, options) when is_map(runner_to_changes_list) do
    runner_to_changes_list
    |> runner_to_changes_list_to_multis(options)
    |> logged_import(options)
  end

  defp logged_import(multis, options) when is_list(multis) and is_map(options) do
    import_id = :erlang.unique_integer([:positive])

    Explorer.Logger.metadata(fn -> import_transactions(multis, options) end, import_id: import_id)
  end

  defp import_transactions(multis, options) when is_list(multis) and is_map(options) do
    grouped_multis =
      multis
      |> Enum.group_by(fn multi -> multi.names end)
      |> Map.to_list()

    grouped_and_sorted_multis =
      grouped_multis
      |> Enum.sort_by(fn {multi_names, _group} ->
        addresses_multi = MapSet.new([:addresses, :created_address_code_indexed_at_transactions])

        acquire_contract_address_tokens_multi_1 =
          MapSet.new([
            :acquire_contract_address_tokens,
            :address_coin_balances,
            :address_coin_balances_daily,
            :blocks,
            :blocks_update_token_holder_counts,
            :delete_address_current_token_balances,
            :delete_address_token_balances,
            :delete_rewards,
            :derive_address_current_token_balances,
            :derive_transaction_forks,
            :fork_transactions,
            :lose_consensus,
            :new_pending_operations,
            :uncle_fetched_block_second_degree_relations
          ])

        acquire_contract_address_tokens_multi_2 =
          MapSet.new([
            :acquire_contract_address_tokens,
            :blocks,
            :blocks_update_token_holder_counts,
            :delete_address_current_token_balances,
            :delete_address_token_balances,
            :delete_rewards,
            :derive_address_current_token_balances,
            :derive_transaction_forks,
            :fork_transactions,
            :lose_consensus,
            :new_pending_operations,
            :uncle_fetched_block_second_degree_relations
          ])

        acquire_blocks_multi =
          MapSet.new([
            :acquire_blocks,
            :acquire_pending_internal_txs,
            :acquire_transactions,
            :internal_transactions,
            :invalid_block_numbers,
            :remove_consensus_of_invalid_blocks,
            :remove_left_over_internal_transactions,
            :update_pending_blocks_status,
            :update_transactions,
            :valid_internal_transactions,
            :valid_internal_transactions_without_first_traces_of_trivial_transactions
          ])

        recollated_transactions_multi =
          MapSet.new([
            :recollated_transactions,
            :transactions
          ])

        acquire_contract_address_tokens_multi_3 =
          MapSet.new([
            :acquire_contract_address_tokens,
            :address_current_token_balances,
            :address_current_token_balances_update_token_holder_counts
          ])

        address_token_balances_multi =
          MapSet.new([
            :address_token_balances,
            :logs,
            :recollated_transactions,
            :token_transfers,
            :tokens,
            :transactions
          ])

        address_coin_balances_multi =
          MapSet.new([
            :address_coin_balances,
            :address_coin_balances_daily
          ])

        address_coin_balances_daily_multi =
          MapSet.new([
            :address_coin_balances_daily
          ])

        block_second_degree_relations_multi =
          MapSet.new([
            :block_second_degree_relations
          ])

        block_rewards_multi =
          MapSet.new([
            :block_rewards
          ])

        address_token_balances_multi_2 =
          MapSet.new([
            :address_token_balances
          ])

        empty_multi = MapSet.new()

        case multi_names do
          ^addresses_multi ->
            0

          ^acquire_contract_address_tokens_multi_1 ->
            1

          ^acquire_contract_address_tokens_multi_2 ->
            1

          ^acquire_blocks_multi ->
            1

          ^recollated_transactions_multi ->
            2

          ^acquire_contract_address_tokens_multi_3 ->
            2

          ^address_token_balances_multi ->
            3

          ^address_token_balances_multi_2 ->
            4

          ^address_coin_balances_multi ->
            4

          ^address_coin_balances_daily_multi ->
            4

          ^block_second_degree_relations_multi ->
            4

          ^block_rewards_multi ->
            4

          ^empty_multi ->
            5

          _multi ->
            4
        end
      end)

    grouped_and_sorted_multis
    |> Enum.map(fn {_, group} ->
      group
      |> Enum.map(fn multi ->
        Task.async(fn ->
          import_transaction(multi, options)
        end)
      end)
      |> Task.yield_many(:timer.seconds(60))
      |> Enum.map(fn {_task, res} -> res end)
      |> Enum.reduce_while({:ok, %{}}, fn res, {:ok, acc_changes} ->
        case res do
          {:ok, changes} ->
            case changes do
              {:ok, changes_map} ->
                {:cont, {:ok, Map.merge(acc_changes, changes_map)}}

              {:error, _, _, _} = error ->
                {:halt, error}
            end

          nil ->
            {:cont, {:ok, acc_changes}}
        end
      end)
    end)
    |> Enum.reduce_while({:ok, %{}}, fn res, {:ok, acc_changes} ->
      case res do
        {:ok, changes} -> {:cont, {:ok, Map.merge(acc_changes, changes)}}
        {:error, _, _, _} = error -> {:halt, error}
      end
    end)
  rescue
    exception in DBConnection.ConnectionError ->
      case Exception.message(exception) do
        "tcp recv: closed" <> _ -> {:error, :timeout}
        _ -> reraise exception, __STACKTRACE__
      end
  end

  defp import_transaction(multi, options) when is_map(options) do
    Repo.logged_transaction(multi, timeout: Map.get(options, :timeout, @transaction_timeout))
  end

  @spec timestamps() :: timestamps
  def timestamps do
    now = DateTime.utc_now()
    %{inserted_at: now, updated_at: now}
  end
end
