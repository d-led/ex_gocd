defmodule ExGoCDWeb.API.JobControllerTest do
  @moduledoc """
  Tests for POST /api/jobs/schedule (GoCD-style: enqueue job for next idle agent).
  """
  use ExGoCDWeb.ConnCase, async: true

  describe "POST /api/jobs/schedule" do
    test "returns 201 and job_id when job is enqueued", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/jobs/schedule", %{})

      assert response = json_response(conn, 201)
      assert response["message"] == "Job scheduled."
      assert String.starts_with?(response["job_id"], "sched-")
    end

    test "accepts pipeline, stage, job in body", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/jobs/schedule", %{
          "pipeline" => "my-pipeline",
          "stage" => "my-stage",
          "job" => "my-job"
        })

      assert json_response(conn, 201)["job_id"]
    end
  end
end
