defmodule ExGoCDWeb.API.Admin.SystemAdminsControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.Accounts

  setup do
    {:ok, _admin} =
      Accounts.create_user(%{
        username: "adminuser",
        display_name: "Admin",
        password: "test123456",
        roles: ["admin"]
      })

    Accounts.create_user(%{username: "vieweruser", display_name: "Viewer"})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{"username" => "adminuser"})

    {:ok, conn: conn}
  end

  test "lists users with the admin role", %{conn: conn} do
    conn = get(conn, "/api/admin/security/system_admins")

    assert json_response(conn, 200) == %{"roles" => [], "users" => ["adminuser"]}
  end
end
