defmodule ExGoCDWeb.API.Admin.AccessTokenController do
  @moduledoc """
  GoCD admin access-token API (api-access-token-v2): an administrator sees, and
  can revoke, the personal access tokens of every user.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts
  alias ExGoCDWeb.API.PersonalAccessTokenJSON

  @doc "GET /api/admin/access_tokens?filter=active|revoked|all"
  def index(conn, params) do
    tokens = Accounts.list_tokens(params["filter"] || "all")

    conn
    |> put_status(:ok)
    |> json(%{
      _links: links(),
      _embedded: %{access_tokens: PersonalAccessTokenJSON.index(%{tokens: tokens})}
    })
  end

  @doc "GET /api/admin/access_tokens/:id"
  def show(conn, %{"id" => id}) do
    case Accounts.get_token(id) do
      nil ->
        not_found(conn, id)

      token ->
        conn |> put_status(:ok) |> json(PersonalAccessTokenJSON.show(%{token: token}))
    end
  end

  @doc "POST /api/admin/access_tokens/:id/revoke"
  def revoke(conn, %{"id" => id}) do
    with %{} = token <- Accounts.get_token(id),
         {:ok, revoked} <- Accounts.revoke_token(token, conn.assigns.current_user.username) do
      conn |> put_status(:ok) |> json(PersonalAccessTokenJSON.show(%{token: revoked}))
    else
      nil -> not_found(conn, id)
      {:error, %Ecto.Changeset{}} -> conn |> put_status(:unprocessable_entity) |> json(%{})
    end
  end

  defp not_found(conn, id) do
    conn |> put_status(:not_found) |> json(%{message: "Access token '#{id}' not found."})
  end

  defp links do
    %{
      self: %{href: "/api/admin/access_tokens"},
      doc: %{href: "https://api.gocd.org/current/#access-token"}
    }
  end
end
