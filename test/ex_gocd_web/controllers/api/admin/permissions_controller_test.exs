defmodule ExGoCDWeb.API.Admin.PermissionsControllerTest do
  use ExGoCDWeb.ConnCase

  test "lists system roles", %{conn: conn} do
    conn = get(conn, "/api/admin/permissions")
    assert conn.status == 200
    body = json_response(conn, 200)
    assert %{"roles" => [%{"role" => "admin"} | _]} = body
    assert %{"pipeline_group_permissions" => _} = body
  end

  test "includes pipeline group permissions when granted", %{conn: conn} do
    {:ok, user} = ExGoCD.Accounts.create_user(%{username: "permtest", display_name: "Perm Test"})
    ExGoCD.Accounts.grant_pipeline_group_permission(user.id, "test-group", "operator")

    conn = get(conn, "/api/admin/permissions")
    assert conn.status == 200
    body = json_response(conn, 200)

    pgps = body["pipeline_group_permissions"]
    assert is_list(pgps)
    matching = Enum.filter(pgps, &(&1["pipeline_group"] == "test-group"))
    assert matching != []
    assert hd(matching)["role"] == "operator"
  end
end
