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

  test "resolves user from DB but does NOT auto-create unknown users by default", %{conn: conn} do
    assert Accounts.get_user_by_username("oauth_user") == nil

    conn =
      conn
      |> put_req_header("x-forwarded-user", "oauth_user")
      |> put_req_header("x-auth-request-name", "OAuth User")
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    # Default: no auto-create. Unknown users fall through to default_user().
    refute get_session(conn, "username")
    refute get_session(conn, "user_id")
    assert Accounts.get_user_by_username("oauth_user") == nil
  end

  test "auto-creates user when EX_GOCD_AUTO_CREATE_USERS=true", %{conn: conn} do
    System.put_env("EX_GOCD_AUTO_CREATE_USERS", "true")
    on_exit(fn -> System.delete_env("EX_GOCD_AUTO_CREATE_USERS") end)

    assert Accounts.get_user_by_username("auto@exgocd.local") == nil

    conn =
      conn
      |> put_req_header("x-forwarded-user", "auto@exgocd.local")
      |> put_req_header("x-auth-request-name", "Auto Created")
      |> put_req_header("x-forwarded-roles", "developer")
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    assert get_session(conn, "username") == "auto@exgocd.local"
    db_user = Accounts.get_user_by_username("auto@exgocd.local")
    assert db_user != nil
    assert "developer" in db_user.roles
  end

  test "auto-creates admin when username in EX_GOCD_ADMIN_USERS", %{conn: conn} do
    System.put_env("EX_GOCD_AUTO_CREATE_USERS", "true")
    System.put_env("EX_GOCD_ADMIN_USERS", "admin@exgocd.local,lead@exgocd.local")

    on_exit(fn ->
      System.delete_env("EX_GOCD_AUTO_CREATE_USERS")
      System.delete_env("EX_GOCD_ADMIN_USERS")
    end)

    conn =
      conn
      |> put_req_header("x-forwarded-user", "admin@exgocd.local")
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    assert get_session(conn, "username") == "admin@exgocd.local"
    db_user = Accounts.get_user_by_username("admin@exgocd.local")
    assert "admin" in db_user.roles
  end

  test "sets session for existing user in DB", %{conn: conn} do
    {:ok, db_user} =
      Accounts.create_user(%{
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
