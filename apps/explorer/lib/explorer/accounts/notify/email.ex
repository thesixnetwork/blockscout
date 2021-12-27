defmodule Explorer.Accounts.Notify.Email do
  @moduledoc """
    Composing an email to sendgrid
  """

  alias BlockScoutWeb.WebRouter.Helpers
  alias Explorer.Accounts.{Identity, Watchlist, WatchlistAddress, WatchlistNotification}
  alias Explorer.{Mailer, Repo}

  import Bamboo.{Email, SendGridHelper}

  def send(notification, %{notify_email: notify}) when notify do
    notification = preload(notification)

    email = compose_email(notification)

    Mailer.deliver_later(email)
  end

  def compose_email(notification) do
    email = new_email(from: sender(), to: email(notification))

    email
    |> with_template(template())
    |> add_dynamic_field("username", username(notification))
    |> add_dynamic_field("address_hash", address_hash_string(notification))
    |> add_dynamic_field("address_name", notification.watchlist_address.name)
    |> add_dynamic_field("transaction_hash", hash_string(notification.transaction_hash))
    |> add_dynamic_field("from_address_hash", hash_string(notification.from_address_hash))
    |> add_dynamic_field("to_address_hash", hash_string(notification.to_address_hash))
    |> add_dynamic_field("block_number", notification.block_number)
    |> add_dynamic_field("amount", notification.amount)
    |> add_dynamic_field("name", notification.name)
    |> add_dynamic_field("tx_fee", notification.tx_fee)
    |> add_dynamic_field("direction", notification.method)
    |> add_dynamic_field("method", notification.method)
    |> add_dynamic_field("transaction_url", transaction_url(notification))
    |> add_dynamic_field("address_url", address_url(notification.watchlist_address.address_hash))
    |> add_dynamic_field("from_url", address_url(notification.from_address_hash))
    |> add_dynamic_field("to_url", address_url(notification.to_address_hash))
    |> add_dynamic_field("block_url", transaction_url(notification))
  end

  def email(%WatchlistNotification{
        watchlist_address: %WatchlistAddress{
          watchlist: %Watchlist{
            identity: %Identity{
              email: email
            }
          }
        }
      }),
      do: email

  def username(%WatchlistNotification{
        watchlist_address: %WatchlistAddress{
          watchlist: %Watchlist{
            identity: %Identity{
              name: name
            }
          }
        }
      }),
      do: name

  def address_hash_string(%WatchlistNotification{
        watchlist_address: %WatchlistAddress{address: address}
      }),
      do: hash_string(address.hash)

  def hash_string(hash) do
    "0x" <> Base.encode16(hash.bytes)
  end

  def direction(notification) do
    affect(notification) <> place(notification)
  end

  def place(%WatchlistNotification{direction: direction}) do
    case direction do
      "incoming" -> "at"
      "outgoing" -> "from"
      _ -> "unknown"
    end
  end

  def affect(%WatchlistNotification{direction: direction}) do
    case direction do
      "incoming" -> "received"
      "outgoing" -> "sent"
      _ -> "unknown"
    end
  end

  def preload(notification) do
    Repo.preload(notification, watchlist_address: [:address, watchlist: :identity])
  end

  def address_url(address_hash) do
    Helpers.address_url(uri(), :show, address_hash)
  end

  def transaction_url(notification) do
    Helpers.transaction_url(uri(), :show, notification.transaction_hash)
  end

  defp uri do
    %URI{scheme: "https", host: host(), path: path()}
  end

  defp host do
    if System.get_env("MIX_ENV") == "prod" do
      "blockscout.com"
    else
      Application.get_env(:block_scout_web, BlockScoutWeb.Endpoint)[:url][:host]
    end
  end

  defp path do
    Application.get_env(:block_scout_web, BlockScoutWeb.Endpoint)[:url][:path]
  end

  defp sender do
    Application.get_env(:explorer, :sendgrid_sender)
  end

  defp template do
    Application.get_env(:explorer, :sendgrid_template)
  end
end
