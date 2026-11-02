defmodule ExGoCDWeb.NoRouteCrashesTest do
  @moduledoc """
  Every route answers — including the ones no test calls for their own sake.

  The CCTray feed, the value-stream-map JSON, raw file transfer and health each
  have a test of their own; the paths below are the rest of those families: the
  `/api_json` spelling the old dashboard fetched, the `/go/files` and
  `/remoting/files` spellings an agent uses, the login page, the stats endpoint.
  Nobody calls them in a test, so a 500 would go unnoticed until a tool outside
  this repository asked for one.
  """
  use ExGoCDWeb.ConnCase, async: true

  @routes [
    "/api/stats",
    "/api_json/go/materials/value_stream_map/0000000000000000/abc123",
    "/api_json/go/pipelines/value_stream_map/absent/1",
    "/api_json/materials/value_stream_map/0000000000000000/abc123",
    "/api_json/pipelines/value_stream_map/absent/1",
    "/auth/login",
    "/files/absent/1/build/1/compile/logs/output.log",
    "/go/files/absent/1/build/1/compile/logs/output.log",
    "/remoting/files/absent/1/build/1/compile/logs/output.log"
  ]

  test "each answers rather than raising", %{conn: conn} do
    ExGoCD.Sweep.assert_all_answered(@routes, &get(conn, &1))
  end

  test "a file that is not there is reported as missing, not as a failure", %{conn: conn} do
    conn = get(conn, "/files/absent/1/build/1/compile/logs/output.log")

    assert conn.status == 404
  end
end
