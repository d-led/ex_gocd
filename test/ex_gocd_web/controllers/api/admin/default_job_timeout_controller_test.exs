defmodule ExGoCDWeb.API.Admin.DefaultJobTimeoutControllerTest do
  use ExGoCDWeb.ConnCase

  test "returns the default job timeout", %{conn: conn} do
    conn = get(conn, "/api/admin/config/server/default_job_timeout")

    assert json_response(conn, 200) == %{"default_job_timeout" => "0"}
  end
end
