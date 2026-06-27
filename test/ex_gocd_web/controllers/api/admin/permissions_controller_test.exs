defmodule ExGoCDWeb.API.Admin.PermissionsControllerTest do
  use ExGoCDWeb.ConnCase

  test "lists system roles with permissions", %{conn: conn} do
    conn = get(conn, "/api/admin/permissions")
    assert conn.status == 200
    assert %{"roles" => [%{"role" => "admin"} | _]} = json_response(conn, 200)
  end
end
