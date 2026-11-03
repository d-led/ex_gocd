defmodule ExGoCDWeb.API.ServerHealthControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.Monitors.DiskSpace
  alias ExGoCD.ServerConfig

  @moduletag :tmp_dir

  test "names a disk the monitor could not measure", %{conn: conn, tmp_dir: tmp_dir} do
    {:ok, _} = ServerConfig.update(%{"artifacts_dir" => Path.join(tmp_dir, "gone")})
    :unknown = DiskSpace.check_now()

    body = json_response(get(conn, "/api/server_health_messages"), 200)

    assert body["health"] == "WARNING"
    assert Enum.any?(body["messages"], &(&1["message"] =~ "could not be determined"))
  end
end
