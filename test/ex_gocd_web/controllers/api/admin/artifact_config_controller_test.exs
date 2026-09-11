defmodule ExGoCDWeb.API.Admin.ArtifactConfigControllerTest do
  use ExGoCDWeb.ConnCase

  test "returns the artifact directory and purge settings", %{conn: conn} do
    conn = get(conn, "/api/admin/config/server/artifact_config")

    body = json_response(conn, 200)
    assert body["artifacts_dir"] == "artifacts"
    assert body["purge_settings"]["purge_start_disk_space"] == 10.0
    assert body["purge_settings"]["purge_upto_disk_space"] == 20.0
  end
end
