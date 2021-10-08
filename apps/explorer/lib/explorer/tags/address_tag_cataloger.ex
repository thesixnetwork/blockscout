defmodule Explorer.Tags.AddressTag.Cataloger do
  @moduledoc """
  Actualizes address tags.
  """

  use GenServer

  alias Explorer.Tags.{AddressTag, AddressToTag}
  alias Explorer.Validator.MetadataRetriever
  alias Poison.Parser

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(args) do
    send(self(), :fetch_tags)

    {:ok, args}
  end

  @impl GenServer
  def handle_info(:fetch_tags, state) do
    # set :faucet tag
    AddressTag.set_tag("faucet")

    # set :validator tag
    AddressTag.set_tag("validator")

    # set :random tag
    AddressTag.set_tag("random")

    # set :omni_bridge tag
    AddressTag.set_tag("omni bridge")

    # set :amb_bridge tag
    AddressTag.set_tag("amb bridge")

    # set :amb_bridge_mediators tag
    AddressTag.set_tag("amb bridge mediators")

    # set :random tag
    AddressTag.set_tag("random")

    # set perpetual tag
    AddressTag.set_tag("perpetual")

    # set dark-forest-0.5 tag
    AddressTag.set_tag("dark forest 0.5")

    # set dark-forest-0.6 tag
    AddressTag.set_tag("dark forest 0.6")

    # set dark-forest-0.6-r2 tag
    AddressTag.set_tag("dark forest 0.6 r2")

    # set dark-forest-0.6-r3 tag
    AddressTag.set_tag("dark forest 0.6 r3")

    # set dark-forest-0.6-r4 tag
    AddressTag.set_tag("dark forest 0.6 r4")

    # set hopr tag
    AddressTag.set_tag("hopr")

    # set test tag
    AddressTag.set_tag("test")

    # set gtgs tag
    AddressTag.set_tag("gtgs")

    # set common chainlink oracle tag
    AddressTag.set_tag("chainlink oracle")

    # set spam tag
    AddressTag.set_tag("spam")

    # set Levinswap tags
    AddressTag.set_tag("lewinswap")
    AddressTag.set_tag("lewinswap farm")
    AddressTag.set_tag("lewinswap stake")

    # set Swarm tag
    AddressTag.set_tag("swarm")

    # set CryptoStamps tag
    AddressTag.set_tag("cryptostamps")

    # set Curve tag
    AddressTag.set_tag("curve")

    # set USELESS MEV MACHINE tag
    AddressTag.set_tag("useless mev machine")

    # set Tornado.Cash tag
    AddressTag.set_tag("tornado cash")

    # set SANA tag
    AddressTag.set_tag("sana")

    # set Black hole tag
    AddressTag.set_tag("black hole")

    # set Rarible Protocol tag
    AddressTag.set_tag("rarible")

    # set Cryptopunks tag
    AddressTag.set_tag("xdai punks")

    # set AoX tag
    AddressTag.set_tag("arbitrum on xdai")

    # set L2 tag
    AddressTag.set_tag("l2")

    # set tag for every chainlink oracle
    create_chainlink_oracle_tag()

    send(self(), :bind_addresses)

    {:noreply, state}
  end

  def handle_info(:bind_addresses, state) do
    # set faucet tag
    set_faucet_tag()

    # set omni bridge tag
    set_omni_tag()

    # set amb bridge tag
    set_amb_tag()

    # set amb bridge mediators tag
    set_amb_mediators_tag()

    # set random aura tag
    set_random_aura_tag()

    # set validator tag
    set_validator_tag()

    # set perpetual tag
    set_perpetual_tag()

    # set DarkForest 0.5 tag
    set_df_0_5_tag()

    # set DarkForest 0.6 tag
    set_df_0_6_tag()

    # set DarkForest 0.6-r2 tag
    set_df_0_6_r2_tag()

    # set DarkForest 0.6-r3 tag
    set_df_0_6_r3_tag()

    # set DarkForest 0.6-r4 tag
    set_df_0_6_r4_tag()

    # set Hopr tag
    set_hopr_tag()

    # set test tag
    set_test_tag()

    # set gtgs tag
    set_gtgs_tag()

    # set spam tag
    set_spam_tag()

    # set Lewinswap tag
    set_lewinswap_tag()
    set_lewinswap_farm_tag()
    set_lewinswap_stake_tag()

    # set chainlink oracle tag
    set_chainlink_oracle_tag()

    # set Swarm tag
    set_swarm_tag()

    # set CryptoStamps tag
    set_cryptostamps_tag()

    # set Curve tag
    set_curve_tag()

    # set USELESS MEV MACHINE tag
    set_useless_mev_machine_tag()

    # set Tornado.Cash tag
    set_tornado_cash_tag()

    # set SANA tag
    set_sana_tag()

    # set Black hole tag
    set_black_hole_tag()

    # set Rarible Protocol tag
    set_rarible_tag()

    # set Cryptopunks tag
    set_cryptopunks_tag()

    # set AoX tag
    set_aox_tag()

    # set L2 tag
    set_l2_tag()

    {:noreply, state}
  end

  def create_chainlink_oracle_tag do
    chainlink_oracles_config = Application.get_env(:block_scout_web, :chainlink_oracles)

    if chainlink_oracles_config do
      chainlink_oracles_config
      |> Parser.parse!(%{keys: :atoms!})
      |> Enum.each(fn %{:name => name, :address => address} ->
        chainlink_tag_name = "chainlink oracle #{String.downcase(name)}"
        AddressTag.set_tag(chainlink_tag_name)
        tag_id = AddressTag.get_tag_id(chainlink_tag_name)
        AddressToTag.set_tag_to_addresses(tag_id, [address])
      end)
    end
  end

  defp set_tag_for_single_env_var_address(env_var, tag) do
    address =
      env_var
      |> System.get_env("")
      |> String.downcase()

    tag_id = AddressTag.get_tag_id(tag)
    AddressToTag.set_tag_to_addresses(tag_id, [address])
  end

  defp set_tag_for_multiple_env_var_addresses(env_vars, tag) do
    addresses =
      env_vars
      |> Enum.map(fn env_var ->
        env_var
        |> System.get_env("")
        |> String.downcase()
      end)

    tag_id = AddressTag.get_tag_id(tag)
    AddressToTag.set_tag_to_addresses(tag_id, addresses)
  end

  defp set_tag_for_multiple_env_var_array_addresses(env_vars, tag) do
    addresses =
      env_vars
      |> Enum.reduce([], fn env_var, acc ->
        env_var
        |> System.get_env("")
        |> String.split(",")
        |> Enum.reduce(acc, fn env_var, acc_inner ->
          addr =
            env_var
            |> String.downcase()

          [addr | acc_inner]
        end)
      end)

    tag_id = AddressTag.get_tag_id(tag)
    AddressToTag.set_tag_to_addresses(tag_id, addresses)
  end

  defp set_tag_for_env_var_multiple_addresses(env_var, tag) do
    addresses =
      env_var
      |> System.get_env("")
      |> String.split(",")
      |> Enum.map(fn env_var ->
        env_var
        |> String.downcase()
      end)

    tag_id = AddressTag.get_tag_id(tag)
    AddressToTag.set_tag_to_addresses(tag_id, addresses)
  end

  defp set_faucet_tag do
    set_tag_for_single_env_var_address("FAUCET_ADDRESS", "faucet")
  end

  defp set_omni_tag do
    set_tag_for_multiple_env_var_addresses(
      ["ETH_OMNI_BRIDGE_MEDIATOR", "BSC_OMNI_BRIDGE_MEDIATOR", "POA_OMNI_BRIDGE_MEDIATOR"],
      "omni bridge"
    )
  end

  defp set_amb_tag do
    set_tag_for_env_var_multiple_addresses("AMB_BRIDGE_ADDRESSES", "amb bridge")
  end

  defp set_amb_mediators_tag do
    set_tag_for_multiple_env_var_array_addresses(
      ["AMB_BRIDGE_MEDIATORS", "CUSTOM_AMB_BRIDGE_MEDIATORS"],
      "amb bridge mediators"
    )
  end

  defp set_random_aura_tag do
    set_tag_for_env_var_multiple_addresses("RANDOM_AURA_CONTRACT", "random")
  end

  defp set_validator_tag do
    validators = MetadataRetriever.fetch_validators_list()
    tag_id = AddressTag.get_tag_id("validator")
    AddressToTag.set_tag_to_addresses(tag_id, validators)
  end

  defp set_perpetual_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_PERP_FI", "perpetual")
  end

  defp set_df_0_5_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_5", "dark forest 0.5")
  end

  defp set_df_0_6_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_6", "dark forest 0.6")
  end

  defp set_df_0_6_r2_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_6_r2", "dark forest 0.6 r2")
  end

  defp set_df_0_6_r3_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_6_r3", "dark forest 0.6 r3")
  end

  defp set_df_0_6_r4_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_DARK_FOREST_V_0_6_r4", "dark forest 0.6 r4")
  end

  defp set_hopr_tag do
    set_tag_for_single_env_var_address("CUSTOM_CONTRACT_ADDRESSES_HOPR", "hopr")
  end

  defp set_test_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_TEST_TOKEN", "test")
  end

  defp set_gtgs_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_GTGS_TOKEN", "gtgs")
  end

  defp set_spam_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_SPAM", "spam")
  end

  defp set_lewinswap_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_LEWINSWAP", "lewinswap")
  end

  defp set_lewinswap_farm_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_LEWINSWAP_FARM", "lewinswap farm")
  end

  defp set_lewinswap_stake_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_LEWINSWAP_STAKE", "lewinswap stake")
  end

  def set_chainlink_oracle_tag do
    chainlink_oracles = chainlink_oracles_list()

    tag_id = AddressTag.get_tag_id("chainlink oracle")
    AddressToTag.set_tag_to_addresses(tag_id, chainlink_oracles)
  end

  defp set_swarm_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_SWARM", "swarm")
  end

  defp set_cryptostamps_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_CRYPTOSTAMPS", "cryptostamps")
  end

  defp set_curve_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_CURVE", "curve")
  end

  defp set_useless_mev_machine_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_USELESS_MEV_MACHINE", "useless mev machine")
  end

  defp set_tornado_cash_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_TORNADO_CASH", "tornado cash")
  end

  defp set_sana_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_SANA", "sana")
  end

  defp set_black_hole_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_BLACK_HOLE", "black hole")
  end

  defp set_rarible_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_RARIBLE", "rarible")
  end

  defp set_cryptopunks_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_CRYPTOPUNKS", "xdai punks")
  end

  defp set_aox_tag do
    set_tag_for_env_var_multiple_addresses("CUSTOM_CONTRACT_ADDRESSES_AOX", "arbitrum on xdai")
  end

  defp set_l2_tag do
    set_tag_for_multiple_env_var_addresses(["CUSTOM_CONTRACT_ADDRESSES_AOX"], "l2")
  end

  defp chainlink_oracles_list do
    chainlink_oracles_config = Application.get_env(:block_scout_web, :chainlink_oracles)

    if chainlink_oracles_config do
      try do
        chainlink_oracles_config
        |> Parser.parse!(%{keys: :atoms!})
        |> Enum.map(fn %{:name => _name, :address => address} -> address end)
      rescue
        _ ->
          []
      end
    else
      []
    end
  end
end
