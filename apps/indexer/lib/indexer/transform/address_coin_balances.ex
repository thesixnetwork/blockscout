defmodule Indexer.Transform.AddressCoinBalances do
  @moduledoc """
  Extracts `Explorer.Chain.Address.CoinBalance` params from other schema's params.
  """

  require Logger

  def params_set(%{} = import_options) do
    Logger.debug("#blocks_importer#: Reducing address coin balances")
    Enum.reduce(import_options, MapSet.new(), &reducer/2)
  end

  defp reducer({:beneficiary_params, beneficiary_params}, acc) when is_list(beneficiary_params) do
    Enum.into(beneficiary_params, acc, fn %{address_hash: address_hash, block_number: block_number}
                                          when is_binary(address_hash) and is_integer(block_number) ->
      Logger.debug("#blocks_importer#: Address coin balances reduced")
      %{address_hash: address_hash, block_number: block_number}
    end)
  end

  defp reducer({:blocks_params, blocks_params}, acc) when is_list(blocks_params) do
    # a block MUST have a miner_hash and number
    Enum.into(blocks_params, acc, fn %{miner_hash: address_hash, number: block_number}
                                     when is_binary(address_hash) and is_integer(block_number) ->
      Logger.debug("#blocks_importer#: Address coin balances reduced 2")
      %{address_hash: address_hash, block_number: block_number}
    end)
  end

  defp reducer({:internal_transactions_params, internal_transactions_params}, initial)
       when is_list(internal_transactions_params) do
    Enum.reduce(internal_transactions_params, initial, &internal_transactions_params_reducer/2)
  end

  defp reducer({:logs_params, logs_params}, acc) when is_list(logs_params) do
    # a log MUST have address_hash and block_number
    logs_params_reduced =
      logs_params
      |> Enum.into(acc, fn
        %{address_hash: address_hash, block_number: block_number}
        when is_binary(address_hash) and is_integer(block_number) ->
          %{address_hash: address_hash, block_number: block_number}

        %{type: "pending"} ->
          nil
      end)
      |> Enum.reject(fn val -> is_nil(val) end)
      |> MapSet.new()

    Logger.debug("#blocks_importer#: Address coin balances reduced 3")
    logs_params_reduced
  end

  defp reducer({:transactions_params, transactions_params}, initial) when is_list(transactions_params) do
    Logger.debug("#blocks_importer#: Address coin balances reduced 4")
    Enum.reduce(transactions_params, initial, &transactions_params_reducer/2)
  end

  defp reducer({:block_second_degree_relations_params, block_second_degree_relations_params}, initial)
       when is_list(block_second_degree_relations_params),
       do: initial

  defp internal_transactions_params_reducer(%{block_number: block_number} = internal_transaction_params, acc)
       when is_integer(block_number) do
    case internal_transaction_params do
      %{type: "call"} ->
        Logger.debug("#blocks_importer#: Address coin balances reduced 5")
        acc

      %{type: "create", error: _} ->
        Logger.debug("#blocks_importer#: Address coin balances reduced 6")
        acc

      %{type: "create", created_contract_address_hash: address_hash} when is_binary(address_hash) ->
        Logger.debug("#blocks_importer#: Address coin balances reduced 7")
        MapSet.put(acc, %{address_hash: address_hash, block_number: block_number})

      %{type: "selfdestruct", from_address_hash: from_address_hash, to_address_hash: to_address_hash}
      when is_binary(from_address_hash) and is_binary(to_address_hash) ->
        Logger.debug("#blocks_importer#: Address coin balances reduced 8")

        acc
        |> MapSet.put(%{address_hash: from_address_hash, block_number: block_number})
        |> MapSet.put(%{address_hash: to_address_hash, block_number: block_number})
    end
  end

  defp transactions_params_reducer(
         %{block_number: block_number, from_address_hash: from_address_hash} = transaction_params,
         initial
       )
       when is_integer(block_number) and is_binary(from_address_hash) do
    # a transaction MUST have a `from_address_hash`
    acc = MapSet.put(initial, %{address_hash: from_address_hash, block_number: block_number})

    # `to_address_hash` is optional
    case transaction_params do
      %{to_address_hash: to_address_hash} when is_binary(to_address_hash) ->
        Logger.debug("#blocks_importer#: Address coin balances reduced 9")
        MapSet.put(acc, %{address_hash: to_address_hash, block_number: block_number})

      _ ->
        Logger.debug("#blocks_importer#: Address coin balances reduced 10")
        acc
    end
  end
end
