defmodule BlockScoutWeb.Account.WatchlistAddressController do
  use BlockScoutWeb, :controller

  alias Explorer.Repo
  alias Explorer.Accounts.WatchlistAddress

  def new(conn, _params) do
    changeset = WatchlistAddress.changeset(%WatchlistAddress{}, %{})
    render(conn, "new.html", watchlist_address: changeset(%{name: "wallet"}))
  end

  def create(conn, %{"watchlist_address" => wa_params}) do
    IO.inspect(wa_params)

    case AddWatchlistAddress.call(current_user(conn).watchlist_id, wa_params) do
      {:ok, _watchlist_address} ->
        conn
        |> put_flash(:info, "Address created!")
        |> redirect(to: watchlist_path(conn, :show))

      {:error, message = message} ->
        conn
        |> put_flash(:error, message)
        |> render("new.html", watchlist_address: changeset(wa_params))
    end
  end

  def show(conn, _params) do
    case current_user(conn) do
      nil ->
        conn
        |> put_flash(:info, "Sign in to see watchlist!")
        |> redirect(to: root())

      %{} = user ->
        render(
          conn,
          "show.html",
          watchlist: watchlist(user)
        )
    end
  end

  defp changeset(params) do
    WatchlistAddress.changeset(%WatchlistAddress{}, params)
  end

  defp watchlist(user) do
    wl = Repo.get(Watchlist, user.watchlist_id)
    Repo.preload(wl, watchlist_addresses: :address)
  end

  defp current_user(conn) do
    get_session(conn, :current_user)
  end

  defp root do
    System.get_env("NETWORK_PATH") || "/"
  end
end
