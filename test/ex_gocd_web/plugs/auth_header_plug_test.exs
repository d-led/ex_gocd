defmodule ExGoCDWeb.Plugs.AuthHeaderPlugTest do
  use ExGoCDWeb.ConnCase, async: true
  alias ExGoCD.Accounts
  alias ExGoCDWeb.Plugs.AuthHeaderPlug

  test "ignores connection if auth headers are missing", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    refute get_session(conn, "username")
    refute get_session(conn, "user_id")
  end

  test "resolves user from DB but does NOT auto-create unknown users", %{conn: conn} do
    assert Accounts.get_user_by_username("oauth_user") == nil

    conn =
      conn
      |> put_req_header("x-forwarded-user", "oauth_user")
      |> put_req_header("x-auth-request-name", "OAuth User")
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    # AuthHeaderPlug no longer auto-creates users.
    # Unknown users fall through to default_user() which provides
    # guest admin access when no admin users exist.
    refute get_session(conn, "username")
    refute get_session(conn, "user_id")
    assert Accounts.get_user_by_username("oauth_user") == nil
  end

  test "sets session for existing user in DB", %{conn: conn} do
    {:ok, db_user} = Accounts.create_user(%{
      username: "oauth_user",
      display_name: "Original Name",
      roles: ["developer"],
      status: "Active"
    })

    conn =
      conn
      |> put_req_header("x-auth-request-user", "oauth_user")
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    assert get_session(conn, "username") == "oauth_user"
    assert get_session(conn, "user_id") == db_user.id
  end
end
