defmodule ExGoCDWeb.Plugs.AuthHeaderPlugTest do
  use ExGoCDWeb.ConnCase
  alias ExGoCDWeb.Plugs.AuthHeaderPlug
  alias ExGoCD.Accounts

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ExGoCD.Repo)
  end

  test "ignores connection if auth headers are missing", %{conn: conn} do
    conn = 
      conn
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    refute get_session(conn, "username")
    refute get_session(conn, "user_id")
  end

  test "resolves user, creates DB record, and sets session on x-forwarded-user header", %{conn: conn} do
    assert Accounts.get_user_by_username("oauth_user") == nil

    conn = 
      conn
      |> put_req_header("x-forwarded-user", "oauth_user")
      |> put_req_header("x-auth-request-name", "OAuth User")
      |> init_test_session(%{})
      |> AuthHeaderPlug.call(%{})

    assert get_session(conn, "username") == "oauth_user"
    assert get_session(conn, "user_id") != nil

    user = Accounts.get_user_by_username("oauth_user")
    assert user != nil
    assert user.display_name == "OAuth User"
  end

  test "uses existing user in DB if already registered", %{conn: conn} do
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
