defmodule ExGoCDWeb.Plugs.AuthHeaderPlug do
  @moduledoc """
  Plug to check for upstream authentication headers (e.g. from oauth2-proxy).
  If found, automatically ensures the user profile is created in the database
  and establishes the session identifiers.
  """
  import Plug.Conn
  alias ExGoCD.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    # Check standard OAuth2 proxy headers
    username =
      get_header(conn, "x-forwarded-user") ||
      get_header(conn, "x-auth-request-user") ||
      get_header(conn, "x-auth-request-preferred-username")

    if username && String.trim(username) != "" do
      username = String.trim(username)
      display_name =
        get_header(conn, "x-auth-request-name") ||
        get_header(conn, "x-auth-request-email") ||
        username

      user = ensure_user(username, display_name)

      conn
      |> put_session("username", user.username)
      |> put_session("user_id", user.id)
    else
      conn
    end
  end

  defp ensure_user(username, display_name) do
    case Accounts.get_user_by_username(username) do
      nil -> bootstrap_user(username, display_name)
      existing -> existing
    end
  end

  defp bootstrap_user(username, display_name) do
    roles = if Accounts.list_users() == [], do: ["admin"], else: []
    {:ok, created} = Accounts.create_user(%{
      "username" => username,
      "display_name" => display_name,
      "roles" => roles,
      "status" => "Active"
    })
    created
  end

  defp get_header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end
end
