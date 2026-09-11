defmodule ExGoCDWeb.API.HealthControllerTest do
  use ExGoCDWeb.ConnCase

  test "reports the server is healthy", %{conn: conn} do
    conn = get(conn, "/api/v1/health")
    assert json_response(conn, 200) == %{"health" => "OK"}
  end
end
