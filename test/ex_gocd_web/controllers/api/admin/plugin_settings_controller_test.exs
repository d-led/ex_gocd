defmodule ExGoCDWeb.API.Admin.PluginSettingsControllerTest do
  use ExGoCDWeb.ConnCase

  test "returns 404 because there is no plugin settings store", %{conn: conn} do
    conn = get(conn, "/api/admin/plugin_settings/anything")

    assert conn.status == 404
    assert %{"message" => _} = json_response(conn, 404)
  end
end
