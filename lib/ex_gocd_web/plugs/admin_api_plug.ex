defmodule ExGoCDWeb.Plugs.AdminApiPlug do
  @moduledoc """
  Ensures the API request is made by a user with admin privileges.

  Mirrors GoCD's `ApiAuthorizationHelper.checkAdminUserAnd403` — rejects
  with 403 Forbidden if the current user lacks the admin role.

  GoCD "open mode": when no admin user is configured in the database,
  all requests are treated as admin (matches GoCD behavior).
  """
  import Plug.Conn
  alias ExGoCD.Accounts

  @doc """
  Initializes the plug with the default options.
  """
  def init(opts), do: opts

  @doc """
  Halts with 403 if the current user is not an admin.

  The current user is resolved from the session (set by `TokenAuthPlug`
  or `AuthHeaderPlug`) via `Accounts.get_current_user/1`.
  """
  def call(conn, _opts) do
    if admin?(conn) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(:forbidden, ~s({"error":"Forbidden — admin access required"}))
      |> halt()
    end
  end

  defp admin?(conn) do
    # GoCD open mode: no admin configured → everyone is admin
    not Accounts.admin_configured?() or
      conn
      |> get_session()
      |> Accounts.get_current_user()
      |> ExGoCD.Accounts.User.has_role?(:admin)
  end
end
