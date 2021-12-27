defmodule UserFromAuth do
  @moduledoc """
  Retrieve the user information from an auth request
  """
  require Logger
  require Poison

  alias Ueberauth.Auth
  alias Explorer.Accounts.Identity

  import Ecto.Query, only: [from: 2]

  def find_or_create(%Auth{} = auth) do
    case List.first(find_identity(auth)) do
      nil -> create_identity(auth)
      %{} = identity -> {:ok, basic_info(auth, identity)}
    end
  end

  defp create_identity(auth) do
    case Explorer.Repo.insert(%Identity{uid: auth.uid}) do
      {:ok, identity} -> {:ok, basic_info(auth, identity)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp find_identity(auth) do
    Explorer.Repo.all(query_identity(auth))
  end

  defp query_identity(auth) do
    from(i in Identity, where: i.uid == ^auth.uid)
  end

  defp basic_info(auth, identity) do
    %{
      id: identity.id,
      uid: auth.uid,
      email: email_from_auth(auth),
      name: name_from_auth(auth),
      nickname: nickname_from_auth(auth),
      avatar: avatar_from_auth(auth)
    }
  end

  # github does it this way
  defp avatar_from_auth(%{info: %{urls: %{avatar_url: image}}}), do: image

  # facebook does it this way
  defp avatar_from_auth(%{info: %{image: image}}), do: image

  # default case if nothing matches
  defp avatar_from_auth(auth) do
    Logger.warn(auth.provider <> " needs to find an avatar URL!")
    Logger.debug(Poison.encode!(auth))
    nil
  end

  defp email_from_auth(%{info: %{email: email}}), do: email

  defp nickname_from_auth(%{info: %{nickname: nickname}}), do: nickname

  defp name_from_auth(auth) do
    if auth.info.name do
      auth.info.name
    else
      name =
        [auth.info.first_name, auth.info.last_name]
        |> Enum.filter(&(&1 != nil and &1 != ""))

      cond do
        length(name) == 0 -> auth.info.nickname
        true -> Enum.join(name, " ")
      end
    end
  end

  #   defp validate_pass(%{other: %{password: ""}}) do
  #     {:error, "Password required"}
  #   end

  #   defp validate_pass(%{other: %{password: pw, password_confirmation: pw}}) do
  #     :ok
  #   end

  #   defp validate_pass(%{other: %{password: _}}) do
  #     {:error, "Passwords do not match"}
  #   end

  #   defp validate_pass(_), do: {:error, "Password Required"}
end
