defmodule Explorer.Visualize.Sol2uml do
  @moduledoc """
    Adapter for sol2uml visualizer with https://github.com/blockscout/blockscout-rs/blob/main/visualizer
  """
  alias HTTPoison.Response
  require Logger

  @post_timeout :infinity
  @request_error_msg "Error while sending request to visualizer microservice"

  def visualize_contracts(body) do
    http_post_request(visualize_contracts_url(), body)
  end

  def http_post_request(url, body) do
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, Jason.encode!(body), headers, recv_timeout: @post_timeout) do
      {:ok, %Response{body: body, status_code: 200}} ->
        proccess_visualizer_response(body)

      {:ok, %Response{body: body, status_code: _}} ->
        proccess_visualizer_response(body)

      {:error, error} ->
        old_truncate = Application.get_env(:logger, :truncate)
        Logger.configure(truncate: :infinity)

        Logger.error(fn ->
          [
            "Error while sending request to visualizer microservice. url: #{url}, body: #{inspect(body, limit: :infinity, printable_limit: :infinity)}: ",
            inspect(error, limit: :infinity, printable_limit: :infinity)
          ]
        end)

        Logger.configure(truncate: old_truncate)
        {:error, @request_error_msg}
    end
  end


  def proccess_visualizer_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        proccess_visualizer_response(decoded)

      _ ->
        {:error, body}
    end
  end

  def proccess_visualizer_response(%{"svg" => svg}) do
    {:ok, svg}
  end

  def proccess_visualizer_response(other), do: {:error, other}

  def visualize_contracts_url, do: "#{base_api_url()}" <> "/solidity:visualizeContracts"

  def base_api_url, do: "#{base_url()}" <> "/api/v1"

  def base_url do
    url = Application.get_env(:explorer, __MODULE__)[:service_url]

    if String.ends_with?(url, "/") do
      url
      |> String.slice(0..(String.length(url) - 2))
    else
      url
    end
  end

  def enabled?, do: Application.get_env(:explorer, __MODULE__)[:enabled]
end
