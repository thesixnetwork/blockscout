defmodule BlockScoutWeb.NFTHelper do
  @moduledoc """
    Module with functions for NFT view
  """
  @ipfs_protocol "ipfs://"

  def get_media_src(nil, _), do: nil

  def get_media_src(%{metadata: metadata} = instance, high_quality_media?) do
    fetch_media_src(metadata, instance.token_contract_address_hash, high_quality_media?)
  end

  def get_media_src(metadata, high_quality_media?) do
    fetch_media_src(metadata, nil, high_quality_media?)
  end

  defp fetch_media_src(metadata, token_contract_address_hash, high_quality_media?) do
    cond do
      metadata["animation_url"] && high_quality_media? ->
        retrieve_image(metadata["animation_url"], token_contract_address_hash)

      metadata["image_url"] ->
        retrieve_image(metadata["image_url"], token_contract_address_hash)

      metadata["image"] ->
        retrieve_image(metadata["image"], token_contract_address_hash)

      metadata["properties"]["image"]["description"] ->
        metadata["properties"]["image"]["description"]

      true ->
        nil
    end
  end

  def external_url(nil), do: nil

  def external_url(instance) do
    result =
      if instance.metadata && instance.metadata["external_url"] do
        instance.metadata["external_url"]
      else
        external_url(nil)
      end

    if !result || (result && String.trim(result)) == "", do: external_url(nil), else: result
  end

  def retrieve_image(image, _) when is_nil(image), do: nil

  def retrieve_image(image, _) when is_map(image) do
    image["description"]
  end

  def retrieve_image(image, token_contract_address_hash) when is_list(image) do
    image_url = image |> Enum.at(0)
    retrieve_image(image_url, token_contract_address_hash)
  end

  def retrieve_image(image_url, token_contract_address_hash) do
    image_url
    |> URI.encode()
    |> compose_ipfs_url(token_contract_address_hash)
  end

  def compose_ipfs_url(nil, _), do: nil

  def compose_ipfs_url(image_url, token_contract_address_hash) do
    image_url_downcase =
      image_url
      |> String.downcase()

    cond do
      image_url_downcase =~ ~r/^ipfs:\/\/ipfs/ ->
        prefix = @ipfs_protocol <> "ipfs/"
        ipfs_link(image_url, prefix)

      image_url_downcase =~ ~r/^ipfs:\/\// ->
        prefix = @ipfs_protocol
        ipfs_link(image_url, prefix)

      true ->
        case URI.parse(image_url) do
          %URI{host: host} ->
            process_kudos_relative_url(image_url, host, token_contract_address_hash)
        end
    end
  end

  def process_kudos_relative_url(image_url, host, token_contract_address_hash) do
    if host do
      image_url
    else
      # Gitcoin Kudos token
      if image_url &&
           Base.encode16(token_contract_address_hash.bytes, case: :lower) ==
             "74e596525c63393f42c76987b6a66f4e52733efa" do
        "https://s.gitcoin.co/static/" <> image_url
      else
        image_url
      end
    end
  end

  defp ipfs_link(image_url, prefix) do
    ipfs_uid = String.slice(image_url, String.length(prefix)..-1)
    "https://ipfs.io/ipfs/" <> ipfs_uid
  end
end
