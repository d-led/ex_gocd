defmodule ExGoCDWeb.API.StageControllerTest do
  @moduledoc """
  The stage API. Two things matter beyond the happy path: that a counter in the
  path is read as a number rather than trusted, and that a stage nobody can find
  is reported as missing rather than as a failure.
  """
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Repo

  @pipeline "stage-api-pipeline"

  setup do
    insert_pipeline(@pipeline)
    instance = insert_pipeline_instance_by_name(@pipeline, 1, DateTime.utc_now())
    stage = insert_stage_instance(instance.id, "build", state: "Failed", result: "Failed")

    %{instance: instance, stage: stage}
  end

  describe "showing a stage" do
    test "describes the stage and its jobs", %{conn: conn, stage: stage} do
      insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

      body = conn |> get("/api/stages/#{@pipeline}/1/build/1") |> json_response(200)

      assert body["name"] == "build"
      assert body["state"] == "Failed"
      assert [%{"name" => "compile"}] = body["jobs"]
    end

    test "says a stage it cannot find is missing", %{conn: conn} do
      body = conn |> get("/api/stages/#{@pipeline}/1/deploy/1") |> json_response(404)

      assert body["message"] =~ "not found"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn} do
      assert conn |> get("/api/stages/#{@pipeline}/not-a-number/build/1") |> json_response(400)
      assert conn |> get("/api/stages/#{@pipeline}/1/build/not-a-number") |> json_response(400)
    end
  end

  describe "the history of a stage" do
    test "lists the runs it has, newest first", %{conn: conn} do
      body = conn |> get("/api/stages/#{@pipeline}/build/history") |> json_response(200)

      assert [%{"counter" => 1, "pipeline_counter" => 1}] = body["stages"]
    end

    test "treats an offset that is not a number as the start", %{conn: conn} do
      body =
        conn
        |> get("/api/stages/#{@pipeline}/build/history?offset=lots")
        |> json_response(200)

      assert length(body["stages"]) == 1
    end
  end

  describe "cancelling a stage" do
    test "cancels a stage that is running", %{conn: conn, stage: stage} do
      stage |> Ecto.Changeset.change(state: "Building", result: "Unknown") |> Repo.update!()

      body = conn |> post("/api/stages/#{@pipeline}/1/build/cancel") |> json_response(200)

      assert body["message"] =~ "cancelled"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn} do
      assert conn |> post("/api/stages/#{@pipeline}/nope/build/cancel") |> json_response(400)
    end
  end

  describe "re-running the failed jobs of a stage" do
    test "says there is nothing to re-run when nothing failed", %{
      conn: conn,
      stage: stage
    } do
      insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

      body =
        conn
        |> post("/api/stages/#{@pipeline}/1/build/1/rerun-failed-jobs")
        |> json_response(422)

      assert body["message"] =~ "No failed jobs"
    end

    test "says a stage it cannot find is missing", %{conn: conn} do
      body =
        conn
        |> post("/api/stages/#{@pipeline}/1/deploy/1/rerun-failed-jobs")
        |> json_response(404)

      assert body["message"] =~ "not found"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn} do
      assert conn
             |> post("/api/stages/#{@pipeline}/1/build/x/rerun-failed-jobs")
             |> json_response(400)
    end
  end
end
