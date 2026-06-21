defmodule ExGoCDWeb.Plugs.TokenAuthPlug do
  @moduledoc """
  A plug to authenticate API requests via HTTP Bearer token.
  If the 'Authorization: Bearer <token>' header is present, it hashes the token and
  verifies it against the active personal access tokens in the database.
  If valid, it sets the current user in the session/connection assigns.
  """
  import Plug.Conn
  alias ExGoCD.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        token = String.trim(token)
        case Accounts.verify_access_token(token) do
          {:ok, user} ->
            conn
            |> put_session("username", user.username)
            |> put_session("user_id", user.id)

          {:error, _reason} ->
            conn
            |> put_status(:unauthorized)
            |> Phoenix.Controller.json(%{error: "Invalid token"})
            |> halt()
        end

      _ ->
        conn
    end
  end
end
