defmodule Indexer.Transform.TransactionActions do
  @moduledoc """
  Helper functions for transforming data for transaction actions.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias ABI.TypeDecoder
  alias Explorer.Chain.Cache.NetVersion
  alias Explorer.Chain.{Hash, Token, TransactionActions}
  alias Explorer.Repo
  alias Explorer.SmartContract.Reader

  @mainnet 1
  @optimism 10
  @polygon 137
  @gnosis 100

  @null_address "0x0000000000000000000000000000000000000000"
  @uniswap_v3_positions_nft "0xc36442b4a4522e871399cd717abdd847ab11fe88"
  @uniswap_v3_factory "0x1f98431c8ad98523631ae4a59f267346ea31f984"
  @uniswap_v3_factory_abi [
    %{
      "inputs" => [
        %{"internalType" => "address", "name" => "", "type" => "address"},
        %{"internalType" => "address", "name" => "", "type" => "address"},
        %{"internalType" => "uint24", "name" => "", "type" => "uint24"}
      ],
      "name" => "getPool",
      "outputs" => [%{"internalType" => "address", "name" => "", "type" => "address"}],
      "stateMutability" => "view",
      "type" => "function"
    }
  ]
  @uniswap_v3_pool_abi [
    %{
      "inputs" => [],
      "name" => "fee",
      "outputs" => [%{"internalType" => "uint24", "name" => "", "type" => "uint24"}],
      "stateMutability" => "view",
      "type" => "function"
    },
    %{
      "inputs" => [],
      "name" => "token0",
      "outputs" => [%{"internalType" => "address", "name" => "", "type" => "address"}],
      "stateMutability" => "view",
      "type" => "function"
    },
    %{
      "inputs" => [],
      "name" => "token1",
      "outputs" => [%{"internalType" => "address", "name" => "", "type" => "address"}],
      "stateMutability" => "view",
      "type" => "function"
    }
  ]
  @erc20_abi [
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "symbol",
      "outputs" => [%{"name" => "", "type" => "string"}],
      "payable" => false,
      "stateMutability" => "view",
      "type" => "function"
    },
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "decimals",
      "outputs" => [%{"name" => "", "type" => "uint8"}],
      "payable" => false,
      "stateMutability" => "view",
      "type" => "function"
    }
  ]

  @doc """
  Returns a list of transaction actions given a list of logs.
  """
  def parse(logs) do
    actions = []

    chain_id = NetVersion.get_version()

    logs
    |> logs_group_by_txs()
    |> clear_actions()

    # handle uniswap v3
    tx_actions =
      if Enum.member?([@mainnet, @optimism, @polygon], chain_id) do
        logs
        |> uniswap_filter_logs()
        |> logs_group_by_txs()
        |> uniswap(actions, chain_id)
      else
        actions
      end

    %{transaction_actions: tx_actions}
  end

  defp uniswap(logs_grouped, actions, chain_id) do
    # create a list of UniswapV3Pool legitimate contracts
    legitimate = uniswap_legitimate_pools(logs_grouped)

    # create tokens cache if not exists
    if :ets.whereis(:tokens_data_cache) == :undefined do
      :ets.new(:tokens_data_cache, [:named_table, :private])
    end

    # iterate for each transaction
    Enum.reduce(logs_grouped, actions, fn {tx_hash, tx_logs}, actions_acc ->
      # trying to find `mint_nft` actions
      actions_acc = uniswap_handle_mint_nft_actions(tx_hash, tx_logs, actions_acc)

      # go through other actions
      Enum.reduce(tx_logs, actions_acc, fn log, acc ->
        acc ++ uniswap_handle_action(log, legitimate, chain_id)
      end)
    end)
  end

  defp uniswap_clarify_token_symbol(symbol, chain_id) do
    if symbol == "WETH" && Enum.member?([@mainnet, @optimism], chain_id) do
      "Ether"
    else
      symbol
    end
  end

  defp uniswap_filter_logs(logs) do
    logs
    |> Enum.filter(fn log ->
      first_topic = String.downcase(log.first_topic)

      Enum.member?(
        [
          "0x7a53080ba414158be7ec69b987b5fb7d07dee101fe85488f0853ae16239d0bde",
          "0x0c396cd989a39f4459b5fa1aed6a9a8dcdbc45908acfd67e028cd568da98982c",
          "0x70935338e69775456a85ddef226c395fb668b63fa0115f5f20610b388e6ca9c0",
          "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67"
        ],
        first_topic
      ) ||
        (first_topic == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef" &&
           String.downcase(log.address_hash) == @uniswap_v3_positions_nft)
    end)
  end

  defp uniswap_handle_action(log, legitimate, chain_id) do
    first_topic = String.downcase(log.first_topic)

    if first_topic == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef" do
      []
    else
      # check UniswapV3Pool contract is legitimate
      pool_address = String.downcase(log.address_hash)

      if Enum.empty?(legitimate[pool_address]) do
        # this is not legitimate uniswap pool, so skip this event
        []
      else
        token_address = legitimate[pool_address]

        token_data = get_token_data(token_address)

        if token_data === false do
          []
        else
          case first_topic do
            "0x7a53080ba414158be7ec69b987b5fb7d07dee101fe85488f0853ae16239d0bde" ->
              # this is Mint event
              uniswap_handle_mint_event(log, token_address, token_data, chain_id)

            "0x0c396cd989a39f4459b5fa1aed6a9a8dcdbc45908acfd67e028cd568da98982c" ->
              # this is Burn event
              uniswap_handle_burn_event(log, token_address, token_data, chain_id)

            "0x70935338e69775456a85ddef226c395fb668b63fa0115f5f20610b388e6ca9c0" ->
              # this is Collect event
              uniswap_handle_collect_event(log, token_address, token_data, chain_id)

            "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67" ->
              # this is Swap event
              uniswap_handle_swap_event(log, token_address, token_data, chain_id)

            _ ->
              []
          end
        end
      end
    end
  end

  defp uniswap_handle_mint_nft_actions(tx_hash, tx_logs, actions_acc) do
    tx_logs
    |> Enum.reduce(%{}, fn log, acc ->
      first_topic = String.downcase(log.first_topic)

      if first_topic == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef" do
        # This is Transfer event for NFT
        from = truncate_address_hash(log.second_topic)

        if from == "0x0000000000000000000000000000000000000000" do
          to = truncate_address_hash(log.third_topic)
          [token_id] = decode_data(log.fourth_topic, [{:uint, 256}])
          mint_nft_ids = Map.put_new(acc, to, [])
          Map.put(mint_nft_ids, to, Enum.reverse([to_string(token_id) | Enum.reverse(mint_nft_ids[to])]))
        else
          acc
        end
      else
        acc
      end
    end)
    |> Enum.reduce(actions_acc, fn {to, ids}, acc ->
      action = %{
        hash: tx_hash,
        protocol: "uniswap_v3",
        data: %{
          name: "Uniswap V3: Positions NFT",
          symbol: "UNI-V3-POS",
          address: @uniswap_v3_positions_nft,
          to: to,
          ids: ids
        },
        type: "mint_nft"
      }

      Enum.reverse([action | Enum.reverse(acc)])
    end)
  end

  defp uniswap_handle_burn_event(log, token_address, token_data, chain_id) do
    [_amount, amount0, amount1] = decode_data(log.data, [{:uint, 128}, {:uint, 256}, {:uint, 256}])

    uniswap_handle_event("burn", amount0, amount1, log, token_address, token_data, chain_id)
  end

  defp uniswap_handle_collect_event(log, token_address, token_data, chain_id) do
    [_recipient, amount0, amount1] = decode_data(log.data, [:address, {:uint, 128}, {:uint, 128}])

    uniswap_handle_event("collect", amount0, amount1, log, token_address, token_data, chain_id)
  end

  defp uniswap_handle_mint_event(log, token_address, token_data, chain_id) do
    [_sender, _amount, amount0, amount1] = decode_data(log.data, [:address, {:uint, 128}, {:uint, 256}, {:uint, 256}])

    uniswap_handle_event("mint", amount0, amount1, log, token_address, token_data, chain_id)
  end

  defp uniswap_handle_swap_event(log, token_address, token_data, chain_id) do
    [amount0, amount1, _sqrt_price_x96, _liquidity, _tick] =
      decode_data(log.data, [{:int, 256}, {:int, 256}, {:uint, 160}, {:uint, 128}, {:int, 24}])

    uniswap_handle_event("swap", amount0, amount1, log, token_address, token_data, chain_id)
  end

  defp uniswap_handle_event(type, amount0, amount1, log, token_address, token_data, chain_id) do
    address0 = Enum.at(token_address, 0)
    decimals0 = token_data[address0].decimals
    symbol0 = uniswap_clarify_token_symbol(token_data[address0].symbol, chain_id)
    address1 = Enum.at(token_address, 1)
    decimals1 = token_data[address1].decimals
    symbol1 = uniswap_clarify_token_symbol(token_data[address1].symbol, chain_id)

    amount0 = fractional(Decimal.new(amount0), decimals0)
    amount1 = fractional(Decimal.new(amount1), decimals1)

    {new_amount0, new_symbol0, new_address0, new_amount1, new_symbol1, new_address1, is_error} =
      if type == "swap" do
        cond do
          String.first(amount0) === "-" and String.first(amount1) !== "-" ->
            {amount1, symbol1, address1, String.slice(amount0, 1, String.length(amount0) - 1), symbol0, address0, false}

          String.first(amount1) === "-" and String.first(amount0) !== "-" ->
            {amount0, symbol0, address0, String.slice(amount1, 1, String.length(amount1) - 1), symbol1, address1, false}

          true ->
            Logger.error("Invalid Swap event in tx #{log.transaction_hash}. Log index: #{log.index}")
            {amount0, symbol0, address0, amount1, symbol1, address1, true}
        end
      else
        {amount0, symbol0, address0, amount1, symbol1, address1, false}
      end

    if is_error do
      []
    else
      [
        %{
          hash: log.transaction_hash,
          protocol: "uniswap_v3",
          data: %{
            amount0: new_amount0,
            symbol0: new_symbol0,
            address0: new_address0,
            amount1: new_amount1,
            symbol1: new_symbol1,
            address1: new_address1
          },
          type: type
        }
      ]
    end
  end

  defp uniswap_legitimate_pools(logs_grouped) do
    pools =
      logs_grouped
      |> Enum.reduce(%{}, fn {_tx_hash, tx_logs}, addresses_acc ->
        tx_logs
        |> Enum.filter(fn log ->
          first_topic = String.downcase(log.first_topic)
          first_topic != "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
        end)
        |> Enum.reduce(addresses_acc, fn log, acc ->
          pool_address = String.downcase(log.address_hash)
          Map.put_new(acc, pool_address, true)
        end)
      end)

    req_resp = uniswap_request_tokens_and_fees(pools)

    if req_resp === false do
      %{}
    else
      case uniswap_request_get_pools(req_resp) do
        {requests_get_pool, responses_get_pool} ->
          requests_get_pool
          |> Enum.zip(responses_get_pool)
          |> Enum.reduce(%{}, fn {request, {_status, response} = _resp}, acc ->
            response =
              case response do
                [item] -> item
                items -> items
              end

            Map.put(
              acc,
              request.pool_address,
              if request.pool_address == String.downcase(response) do
                [token0, token1, _] = request.args
                [token0, token1]
              else
                []
              end
            )
          end)

        _ ->
          %{}
      end
    end
  end

  defp uniswap_request_get_pools({requests_tokens_and_fees, responses_tokens_and_fees}) do
    requests_get_pool =
      requests_tokens_and_fees
      |> Enum.zip(responses_tokens_and_fees)
      |> Enum.reduce(%{}, fn {request, {_status, response} = _resp}, acc ->
        response =
          case response do
            [item] -> item
            items -> items
          end

        acc = Map.put_new(acc, request.contract_address, %{token0: "", token1: "", fee: ""})
        item = Map.put(acc[request.contract_address], atomized_key(request.method_id), response)
        Map.put(acc, request.contract_address, item)
      end)
      |> Enum.map(fn {pool_address, pool} ->
        token0 = if is_address_correct?(pool.token0), do: String.downcase(pool.token0), else: @null_address
        token1 = if is_address_correct?(pool.token1), do: String.downcase(pool.token1), else: @null_address
        fee = if pool.fee == "", do: 0, else: pool.fee

        # we will call getPool(token0, token1, fee) public getter
        %{
          pool_address: pool_address,
          contract_address: @uniswap_v3_factory,
          method_id: "1698ee82",
          args: [token0, token1, fee]
        }
      end)

    max_retries = Application.get_env(:explorer, :token_functions_reader_max_retries)

    {responses_get_pool, error_messages} =
      read_contracts_with_retries(requests_get_pool, @uniswap_v3_factory_abi, max_retries)

    if !Enum.empty?(error_messages) or Enum.count(requests_get_pool) != Enum.count(responses_get_pool) do
      Logger.error(
        "Cannot read Uniswap V3 Factory contract getPool public getter. Error messages: #{Enum.join(error_messages, ", ")}"
      )

      false
    else
      {requests_get_pool, responses_get_pool}
    end
  end

  defp uniswap_request_tokens_and_fees(pools) do
    requests =
      pools
      |> Enum.map(fn {pool_address, _} ->
        # we will call token0(), token1(), fee() public getters
        Enum.map(["0dfe1681", "d21220a7", "ddca3f43"], fn method_id ->
          %{
            contract_address: pool_address,
            method_id: method_id,
            args: []
          }
        end)
      end)
      |> List.flatten()

    max_retries = Application.get_env(:explorer, :token_functions_reader_max_retries)

    {responses, error_messages} = read_contracts_with_retries(requests, @uniswap_v3_pool_abi, max_retries)

    if !Enum.empty?(error_messages) or Enum.count(requests) != Enum.count(responses) do
      Logger.error(
        "Cannot read Uniswap V3 Pool contract public getters: token0(), token1(), fee(). Error messages: #{Enum.join(error_messages, ", ")}. Pools: #{Enum.join(Map.keys(pools), ", ")}"
      )

      false
    else
      {requests, responses}
    end
  end

  defp atomized_key("token0"), do: :token0
  defp atomized_key("token1"), do: :token1
  defp atomized_key("fee"), do: :fee
  defp atomized_key("getPool"), do: :getPool
  defp atomized_key("symbol"), do: :symbol
  defp atomized_key("decimals"), do: :decimals
  defp atomized_key("0dfe1681"), do: :token0
  defp atomized_key("d21220a7"), do: :token1
  defp atomized_key("ddca3f43"), do: :fee
  defp atomized_key("1698ee82"), do: :getPool
  defp atomized_key("95d89b41"), do: :symbol
  defp atomized_key("313ce567"), do: :decimals

  defp clear_actions(logs_grouped) do
    logs_grouped
    |> Enum.each(fn {tx_hash, _} ->
      Repo.delete_all(from(ta in TransactionActions, where: ta.hash == ^tx_hash))
    end)
  end

  defp decode_data("0x", types) do
    for _ <- types, do: nil
  end

  defp decode_data("0x" <> encoded_data, types) do
    encoded_data
    |> Base.decode16!(case: :mixed)
    |> TypeDecoder.decode_raw(types)
  end

  defp fractional(%Decimal{} = amount, decimals) do
    amount.sign
    |> Decimal.new(amount.coef, amount.exp - decimals)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp get_token_data(token_addresses) do
    # first, we're trying to read token data from the cache.
    # if the cache is empty, we read that from DB.
    # if tokens are not in the cache, nor in the DB, read them through RPC.
    token_data =
      token_addresses
      |> get_token_data_from_cache()
      |> get_token_data_from_db()
      |> get_token_data_from_rpc()

    if Enum.any?(token_data, fn {_, token} ->
         is_nil(token.symbol) or token.symbol == "" or is_nil(token.decimals)
       end) do
      false
    else
      token_data
    end
  end

  defp get_token_data_from_cache(token_addresses) do
    token_addresses
    |> Enum.reduce(%{}, fn address, acc ->
      Map.put(
        acc,
        address,
        case :ets.lookup(:tokens_data_cache, address) do
          [{_, value}] -> value
          _ -> %{symbol: nil, decimals: nil}
        end
      )
    end)
  end

  defp get_token_data_from_db(token_data_from_cache) do
    # a list of token addresses which we should select from the database
    select_tokens_from_db =
      token_data_from_cache
      |> Enum.reduce([], fn {address, data}, acc ->
        if is_nil(data.symbol) or is_nil(data.decimals) do
          Enum.reverse([address | Enum.reverse(acc)])
        else
          acc
        end
      end)

    if Enum.empty?(select_tokens_from_db) do
      # we don't need to read data from db, so will use the cache
      token_data_from_cache
    else
      # try to read token symbols and decimals from the database and then save to the cache
      query =
        from(
          t in Token,
          where: t.contract_address_hash in ^select_tokens_from_db,
          select: {t.symbol, t.decimals, t.contract_address_hash}
        )

      query
      |> Repo.all()
      |> Enum.reduce(token_data_from_cache, fn {symbol, decimals, contract_address_hash}, token_data_acc ->
        contract_address_hash = String.downcase(Hash.to_string(contract_address_hash))

        symbol =
          if is_nil(symbol) or symbol == "" do
            # if db field is empty, take it from the cache
            token_data_acc[contract_address_hash].symbol
          else
            symbol
          end

        decimals =
          if is_nil(decimals) do
            # if db field is empty, take it from the cache
            token_data_acc[contract_address_hash].decimals
          else
            decimals
          end

        new_data = %{symbol: symbol, decimals: decimals}

        :ets.insert(:tokens_data_cache, {contract_address_hash, new_data})

        Map.put(token_data_acc, contract_address_hash, new_data)
      end)
    end
  end

  defp get_token_data_from_rpc(token_data) do
    token_addresses =
      token_data
      |> Enum.reduce([], fn {address, data}, acc ->
        if is_nil(data.symbol) or data.symbol == "" or is_nil(data.decimals) do
          Enum.reverse([address | Enum.reverse(acc)])
        else
          acc
        end
      end)

    if Enum.empty?(token_addresses) do
      token_data
    else
      req_resp = get_token_data_request_symbol_decimals(token_addresses)

      if req_resp === false do
        token_data
      else
        {requests, responses} = req_resp

        requests
        |> Enum.zip(responses)
        |> Enum.reduce(token_data, fn {request, {_status, response} = _resp}, token_data_acc ->
          response =
            case response do
              [item] -> item
              items -> items
            end

          data = token_data_acc[request.contract_address]

          new_data =
            if atomized_key(request.method_id) == :symbol do
              %{data | symbol: response}
            else
              %{data | decimals: response}
            end

          :ets.insert(:tokens_data_cache, {request.contract_address, new_data})

          Map.put(token_data_acc, request.contract_address, new_data)
        end)
      end
    end
  end

  defp get_token_data_request_symbol_decimals(token_addresses) do
    requests =
      token_addresses
      |> Enum.map(fn address ->
        # we will call symbol() and decimals() public getters
        Enum.map(["95d89b41", "313ce567"], fn method_id ->
          %{
            contract_address: address,
            method_id: method_id,
            args: []
          }
        end)
      end)
      |> List.flatten()

    max_retries = Application.get_env(:explorer, :token_functions_reader_max_retries)
    {responses, error_messages} = read_contracts_with_retries(requests, @erc20_abi, max_retries)

    if !Enum.empty?(error_messages) or Enum.count(requests) != Enum.count(responses) do
      Logger.error(
        "Cannot read symbol and decimals of an ERC-20 token contract. Error messages: #{Enum.join(error_messages, ", ")}. Addresses: #{Enum.join(token_addresses, ", ")}"
      )

      false
    else
      {requests, responses}
    end
  end

  defp is_address_correct?(address) do
    String.match?(address, ~r/^0x[[:xdigit:]]{40}$/i)
  end

  defp logs_group_by_txs(logs) do
    logs
    |> Enum.reduce(%{}, fn log, acc ->
      acc = Map.put_new(acc, log.transaction_hash, [])
      Map.put(acc, log.transaction_hash, Enum.reverse([log | Enum.reverse(acc[log.transaction_hash])]))
    end)
  end

  defp read_contracts_with_retries(requests, abi, retries_left) when retries_left > 0 do
    responses = Reader.query_contracts(requests, abi)

    error_messages =
      Enum.reduce(responses, [], fn {status, error_message}, acc ->
        acc ++
          if status == :error do
            [error_message]
          else
            []
          end
      end)

    if Enum.empty?(error_messages) do
      {responses, []}
    else
      retries_left = retries_left - 1

      if retries_left == 0 do
        {[], Enum.uniq(error_messages)}
      else
        read_contracts_with_retries(requests, abi, retries_left)
      end
    end
  end

  defp truncate_address_hash(nil), do: "0x0000000000000000000000000000000000000000"

  defp truncate_address_hash("0x000000000000000000000000" <> truncated_hash) do
    "0x#{truncated_hash}"
  end
end
