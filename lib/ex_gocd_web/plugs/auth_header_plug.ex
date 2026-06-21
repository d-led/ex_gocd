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

      forwarded_roles = parse_roles_header(conn)

      user = ensure_user(username, display_name, forwarded_roles)

      if user do
        conn
        |> put_session("username", user.username)
        |> put_session("user_id", user.id)
        |> put_session("roles", user.roles)
      else
        conn
      end
    else
      conn
    end
  end

  defp ensure_user(username, display_name, forwarded_roles) do
    case Accounts.get_user_by_username(username) do
      nil ->
        if auto_create_enabled?() do
          roles = resolve_roles(username, forwarded_roles)
          case Accounts.create_user(%{
            username: username,
            display_name: display_name,
            roles: roles,
            email: username
          }) do
            {:ok, user} -> user
            {:error, _} -> nil
          end
        else
          nil
        end

      existing ->
        existing
    end
  end

  defp auto_create_enabled? do
    System.get_env("EX_GOCD_AUTO_CREATE_USERS", "false") == "true"
  end

  defp resolve_roles(username, forwarded_roles) do
    admin_users = System.get_env("EX_GOCD_ADMIN_USERS", "") |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if username in admin_users do
      ["admin"] ++ (forwarded_roles -- ["admin"])
    else
      forwarded_roles
    end
  end

  defp parse_roles_header(conn) do
    raw =
      get_header(conn, "x-forwarded-roles") ||
      get_header(conn, "x-forwarded-groups") ||
      get_header(conn, "x-auth-request-groups") ||
      ""

    raw |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

  defp get_header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end
end
