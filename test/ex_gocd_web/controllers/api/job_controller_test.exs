defmodule ExGoCDWeb.API.JobControllerTest do
  @moduledoc """
  The job API: scheduling a job for the next idle agent, and reading one back.
  """
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures

  @pipeline "job-api-pipeline"

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

  describe "GET /api/jobs/:pipeline/:counter/:stage/:stage_counter/:job" do
    setup do
      insert_pipeline(@pipeline)
      instance = insert_pipeline_instance_by_name(@pipeline, 1, DateTime.utc_now())
      stage = insert_stage_instance(instance.id, "build", state: "Failed", result: "Failed")
      insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

      :ok
    end

    test "describes the job as it is stored", %{conn: conn} do
      body =
        conn
        |> get("/api/jobs/#{@pipeline}/1/build/1/compile")
        |> json_response(200)

      assert body["name"] == "compile"
      assert body["state"] == "Completed"
      assert body["result"] == "Passed"
    end

    test "says a job it cannot find is missing", %{conn: conn} do
      body = conn |> get("/api/jobs/#{@pipeline}/1/build/1/test") |> json_response(404)

      assert body["message"] =~ "not found"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn} do
      assert conn |> get("/api/jobs/#{@pipeline}/1/build/x/compile") |> json_response(400)

      assert conn
             |> get("/api/jobs/#{@pipeline}/nope/build/1/compile")
             |> json_response(400)
    end
  end
end
