defmodule ExGoCDWeb.API.StageControllerTest do
  @moduledoc """
  The stage API. Two things matter beyond the happy path: that a counter in the
  path is read as a number rather than trusted, and that a stage nobody can find
  is reported as missing rather than as a failure.
  """
  use ExGoCDWeb.ConnCase, async: true

  import Ecto.Query
  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{JobInstance, StageInstance}
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

      body =
        conn
        |> confirmed()
        |> post("/api/stages/#{@pipeline}/1/build/cancel")
        |> json_response(200)

      assert body == %{"message" => "Stage cancelled successfully."}
    end

    test "asks an empty request to confirm first, as GoCD does", %{conn: conn, stage: stage} do
      stage |> Ecto.Changeset.change(state: "Building", result: "Unknown") |> Repo.update!()

      body = conn |> post("/api/stages/#{@pipeline}/1/build/cancel") |> json_response(400)

      assert body["message"] =~ "X-GoCD-Confirm"
      assert Repo.get!(StageInstance, stage.id).state == "Building"
    end

    test "cancels the stage instance the path names, not whichever row came first", %{
      conn: conn,
      instance: instance,
      stage: first
    } do
      first |> Ecto.Changeset.change(state: "Completed", result: "Passed") |> Repo.update!()

      second = insert_stage_instance(instance.id, "build", counter: 2)
      insert_job_instance_unassigned(second.id, "compile", DateTime.utc_now())

      conn
      |> confirmed()
      |> post("/api/stages/#{@pipeline}/1/build/2/cancel")
      |> json_response(200)

      assert Repo.get!(StageInstance, second.id).state == "Cancelled"
      assert Repo.get!(StageInstance, first.id).state == "Completed"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn} do
      assert conn
             |> confirmed()
             |> post("/api/stages/#{@pipeline}/nope/build/cancel")
             |> json_response(400)

      assert conn
             |> confirmed()
             |> post("/api/stages/#{@pipeline}/1/build/nope/cancel")
             |> json_response(400)
    end
  end

  describe "running the failed jobs of a stage" do
    setup %{stage: stage} do
      %{job: insert_job_instance_unassigned(stage.id, "compile", DateTime.utc_now())}
    end

    test "accepts the request and reschedules the failed job", %{conn: conn, job: job} do
      job |> Ecto.Changeset.change(state: "Completed", result: "Failed") |> Repo.update!()

      body =
        conn
        |> confirmed()
        |> post("/go/api/stages/#{@pipeline}/1/build/1/run-failed-jobs")
        |> json_response(202)

      assert body == %{"message" => "Request to rerun jobs accepted"}
      assert Repo.get!(JobInstance, job.id).state == "Scheduled"
    end

    test "says there is nothing to re-run when nothing failed", %{conn: conn, job: job} do
      job |> Ecto.Changeset.change(state: "Completed", result: "Passed") |> Repo.update!()

      body =
        conn
        |> confirmed()
        |> post("/api/stages/#{@pipeline}/1/build/1/run-failed-jobs")
        |> json_response(422)

      assert body["message"] =~ "No failed jobs"
    end

    test "says a stage it cannot find is missing", %{conn: conn} do
      body =
        conn
        |> confirmed()
        |> post("/api/stages/#{@pipeline}/1/deploy/1/run-failed-jobs")
        |> json_response(404)

      assert body["message"] =~ "not found"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn} do
      assert conn
             |> confirmed()
             |> post("/api/stages/#{@pipeline}/1/build/x/run-failed-jobs")
             |> json_response(400)
    end
  end

  describe "running selected jobs of a stage" do
    test "accepts the job names it was given", %{conn: conn, stage: stage} do
      insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

      body =
        conn
        |> post_json("/api/stages/#{@pipeline}/1/build/1/run-selected-jobs", %{
          jobs: ["compile"]
        })
        |> json_response(202)

      assert body == %{"message" => "Request to rerun jobs accepted"}
    end

    test "names no jobs as a bad request", %{conn: conn} do
      assert conn
             |> post_json("/api/stages/#{@pipeline}/1/build/1/run-selected-jobs", %{jobs: []})
             |> json_response(400)
    end

    test "refuses job names that are not in the stage", %{conn: conn, stage: stage} do
      insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

      body =
        conn
        |> post_json("/api/stages/#{@pipeline}/1/build/1/run-selected-jobs", %{
          jobs: ["no-such-job"]
        })
        |> json_response(422)

      assert body["message"] =~ "belong to this stage"
    end
  end

  describe "running a stage that waits for approval" do
    setup do
      name = "run-stage-pipeline-#{System.unique_integer([:positive])}"
      {pipeline, _first, second} = insert_pipeline_with_two_stages(name)
      {:ok, instance} = Pipelines.trigger_pipeline(name)

      # Finish the first stage so the manual second one is left awaiting.
      [first_instance] =
        Repo.all(
          from(si in StageInstance,
            where: si.pipeline_instance_id == ^instance.id and si.state == "Building"
          )
        )

      [job] =
        Repo.all(from(ji in JobInstance, where: ji.stage_instance_id == ^first_instance.id))

      :ok = Pipelines.complete_job_instance(job.id, "Passed")

      %{pipeline: pipeline, counter: instance.counter, stage: second.name}
    end

    test "schedules the awaiting stage, as the documented curl does", %{
      conn: conn,
      pipeline: pipeline,
      counter: counter,
      stage: stage
    } do
      body =
        conn
        |> confirmed()
        |> post("/go/api/stages/#{pipeline.name}/#{counter}/#{stage}/run")
        |> json_response(202)

      assert body == %{
               "message" =>
                 "Request to schedule stage #{pipeline.name}/#{counter}/#{stage} accepted"
             }

      assert %{state: "Building"} = awaiting_instance(pipeline.name, counter, stage)
    end

    test "asks an empty request to confirm first", %{
      conn: conn,
      pipeline: pipeline,
      counter: counter,
      stage: stage
    } do
      body =
        conn |> post("/api/stages/#{pipeline.name}/#{counter}/#{stage}/run") |> json_response(400)

      assert body["message"] =~ "X-GoCD-Confirm"
      assert %{state: "Awaiting"} = awaiting_instance(pipeline.name, counter, stage)
    end

    test "refuses a stage that is not waiting for approval", %{
      conn: conn,
      pipeline: pipeline,
      counter: counter
    } do
      body =
        conn
        |> confirmed()
        |> post("/api/stages/#{pipeline.name}/#{counter}/build/run")
        |> json_response(422)

      assert body["message"] =~ "Could not schedule stage"
    end

    test "answers a counter that is not a number as a bad request", %{
      conn: conn,
      pipeline: pipeline,
      stage: stage
    } do
      assert conn
             |> confirmed()
             |> post("/api/stages/#{pipeline.name}/nope/#{stage}/run")
             |> json_response(400)
    end

    defp awaiting_instance(pipeline_name, counter, stage_name) do
      Repo.one!(
        from(si in StageInstance,
          join: pi in assoc(si, :pipeline_instance),
          join: p in assoc(pi, :pipeline),
          where: p.name == ^pipeline_name and pi.counter == ^counter and si.name == ^stage_name
        )
      )
    end
  end

  # The header's presence is the confirmation; GoCD does not read its value.
  defp confirmed(conn), do: put_req_header(conn, "x-gocd-confirm", "true")

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end
end
