defmodule BlockScoutWeb.Account.TagAddressController do
  use BlockScoutWeb, :controller

  alias Ecto.Changeset
  alias Explorer.Accounts.TagAddress
  alias Explorer.Repo

  import BlockScoutWeb.Account.AuthController, only: [authenticate!: 1, current_user: 1]
  import Ecto.Query, only: [from: 2]

  def index(conn, _params) do
    case current_user(conn) do
      nil ->
        conn
        |> redirect(to: root())

      %{} = user ->
        render(
          conn,
          "index.html",
          address_tags: address_tags(user)
        )
    end
  end

  def new(conn, _params) do
    authenticate!(conn)

    render(conn, "new.html", new_tag: new_tag())
  end

  def create(conn, %{"tag_address" => params}) do
    current_user = authenticate!(conn)

    case AddTagAddress.call(current_user.id, params) do
      {:ok, _tag_address} ->
        conn
        |> redirect(to: tag_address_path(conn, :index))

      {:error, message = message} ->
        conn
        |> render("new.html", new_tag: changeset_with_error(params, message))
    end
  end

  def delete(conn, %{"id" => id}) do
    current_user = authenticate!(conn)

    TagAddress
    |> Repo.get_by(id: id, identity_id: current_user.id)
    |> Repo.delete()

    conn
    |> redirect(to: tag_address_path(conn, :index))
  end

  def address_tags(user) do
    query =
      from(ta in TagAddress,
        where: ta.identity_id == ^user.id
      )

    query
    |> Repo.all()
  end

  defp new_tag, do: TagAddress.changeset(%TagAddress{}, %{})

  defp changeset_with_error(params, message) do
    %{changeset(params) | action: :insert}
    |> Changeset.add_error(:address_hash, message)
  end

  defp changeset(params) do
    TagAddress.changeset(%TagAddress{}, params)
  end

  defp root do
    System.get_env("NETWORK_PATH") || "/"
  end
end
