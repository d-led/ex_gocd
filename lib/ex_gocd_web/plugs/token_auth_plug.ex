defmodule ExGoCDWeb.Plugs.TokenAuthPlug do
  @moduledoc """
  Authenticates requests via Bearer token or delegates to configured AuthProvider
  plugin (LDAP, OAuth, GitHub, etc.).

  Flow:
  1. Bearer token in Authorization header → verify via DB access tokens
  2. If no token, consult Plugin.Registry.get(:auth_provider)
     → delegate to plugin's authenticate/1
  3. Fall back to guest user (GoCD open mode)
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
        # No bearer token — try AuthProvider plugin
        case ExGoCD.Plugin.Registry.get(:auth_provider) do
          nil ->
            # No plugin configured — fall through to guest
            conn

          mod ->
            case mod.authenticate(conn_to_auth_map(conn)) do
              {:ok, user} ->
                conn
                |> put_session("username", user.username)
                |> put_session("user_id", user.id)

              {:error, _reason} ->
                conn
            end
        end
    end
  end

  defp conn_to_auth_map(conn) do
    %{
      username: get_session(conn, "username"),
      password: get_session(conn, "password"),
      params: conn.params,
      peer_data: Plug.Conn.get_peer_data(conn)
    }
  end
end
