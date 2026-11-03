defmodule ExGoCDWeb.API.Admin.DefaultJobTimeoutControllerTest do
  use ExGoCDWeb.ConnCase

  test "reports the timeout, which starts at zero", %{conn: conn} do
    conn = get(conn, "/api/admin/config/server/default_job_timeout")

    assert %{
             "default_job_timeout" => "0",
             "_links" => %{
               "self" => %{"href" => "/api/admin/config/server/default_job_timeout"}
             }
           } = json_response(conn, 200)
  end

  describe "the documented write" do
    test "POST stores the timeout the API then reports", %{conn: conn} do
      conn =
        post(conn, "/go/api/admin/config/server/default_job_timeout", %{
          default_job_timeout: "10"
        })

      assert %{"default_job_timeout" => "10"} = json_response(conn, 200)

      assert %{"default_job_timeout" => "10"} =
               json_response(
                 get(build_conn(), "/go/api/admin/config/server/default_job_timeout"),
                 200
               )
    end

    test "PUT means the same as POST", %{conn: conn} do
      conn =
        put(conn, "/api/admin/config/server/default_job_timeout", %{
          default_job_timeout: "25"
        })

      assert %{"default_job_timeout" => "25"} = json_response(conn, 200)
    end

    test "refuses a timeout that is not a number", %{conn: conn} do
      conn =
        post(conn, "/go/api/admin/config/server/default_job_timeout", %{
          default_job_timeout: "soon"
        })

      assert %{"errors" => %{"default_job_timeout" => [message]}} =
               json_response(conn, 422)

      assert message =~ "should be a valid number"
    end
  end
end
