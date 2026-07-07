defmodule ExGoCDWeb.Plugs.AdminApiPlugTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCDWeb.Plugs.AdminApiPlug

  setup do
    # Clean up any test users created during tests
    on_exit(fn ->
      # Ensure we clean up admin users that would enable security mode
      {:ok, _} =
        Ecto.Adapters.SQL.query(
          ExGoCD.Repo,
          "DELETE FROM users WHERE username LIKE 'admin_api_test_%'"
        )
    end)

    :ok
  end

  describe "open mode (no admin configured)" do
    test "allows all requests when no admin user exists", %{conn: conn} do
      # Sanity: ensure no admin exists
      refute Accounts.admin_configured?()

      conn =
        conn
        |> init_test_session(%{})
        |> AdminApiPlug.call(%{})

      refute conn.halted
      assert conn.status != 403
    end

    test "allows unauthenticated guest in open mode", %{conn: _conn} do
      refute Accounts.admin_configured?()

      # Even without any session data
      conn =
        build_conn()
        |> AdminApiPlug.call(%{})

      refute conn.halted
    end
  end

  describe "security mode (admin configured)" do
    setup do
      {:ok, admin} =
        Accounts.create_user(%{
          username: "admin_api_test_admin",
          display_name: "Test Admin",
          roles: ["admin"],
          status: "Active"
        })

      {:ok, user} =
        Accounts.create_user(%{
          username: "admin_api_test_user",
          display_name: "Test User",
          roles: [],
          status: "Active"
        })

      {:ok, admin: admin, user: user}
    end

    test "allows request from admin user", %{conn: conn, admin: admin} do
      assert Accounts.admin_configured?()

      conn =
        conn
        |> init_test_session(%{"username" => admin.username, "user_id" => admin.id})
        |> AdminApiPlug.call(%{})

      refute conn.halted
    end

    test "rejects request from non-admin user with 403", %{conn: conn, user: user} do
      assert Accounts.admin_configured?()

      conn =
        conn
        |> init_test_session(%{"username" => user.username, "user_id" => user.id})
        |> AdminApiPlug.call(%{})

      assert conn.halted
      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["error"] =~ "admin access required"
    end

    test "rejects request from unauthenticated guest with 403", %{conn: conn} do
      assert Accounts.admin_configured?()

      conn =
        conn
        |> init_test_session(%{})
        |> AdminApiPlug.call(%{})

      assert conn.halted
      assert conn.status == 403
    end
  end
end
