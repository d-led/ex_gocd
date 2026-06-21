defmodule ExGoCDWeb.API.PipelineOperationsControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  setup %{conn: conn} do
    # Clean up DB before each test
    Repo.delete_all(Pipelines.Pipeline)
    Repo.delete_all(ExGoCD.Accounts.User)

    # Initialize session map on conn so get_session plug works
    conn = Plug.Test.init_test_session(conn, %{})

    {:ok, conn: conn}
  end

  describe "POST /api/pipelines/:pipeline_name/pause" do
    test "pauses pipeline successfully in open mode", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-pause", group: "test"})

      conn = post(conn, ~p"/api/pipelines/#{pipeline.name}/pause", %{"pause_cause" => "debugging failure"})

      assert response = json_response(conn, 200)
      assert response["message"] == "Pipeline 'test-api-pause' paused successfully."

      # Verify database state
      updated = Repo.get!(Pipelines.Pipeline, pipeline.id)
      assert updated.paused == true
      assert updated.paused_by == "guest"
      assert updated.pause_cause == "debugging failure"
      assert updated.paused_at != nil
    end

    test "requires admin/developer permissions when security is active", %{conn: conn} do
      # Seed users
      {:ok, _} = ExGoCD.Accounts.create_user(%{username: "admin", display_name: "Admin", roles: ["admin"], status: "Active"})
      {:ok, _} = ExGoCD.Accounts.create_user(%{username: "viewer", display_name: "Viewer", roles: [], status: "Active"})

      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-auth-pause", group: "test"})

      # Try as viewer - forbidden
      viewer_conn = log_in_as(conn, "viewer")
      viewer_conn = post(viewer_conn, ~p"/api/pipelines/#{pipeline.name}/pause", %{"pause_cause" => "downtime"})
      assert json_response(viewer_conn, 403) == %{"error" => "Forbidden"}

      # Try as admin - works
      admin_conn = log_in_as(conn, "admin")
      admin_conn = post(admin_conn, ~p"/api/pipelines/#{pipeline.name}/pause", %{"pause_cause" => "downtime"})
      assert response = json_response(admin_conn, 200)
      assert response["message"] == "Pipeline 'test-api-auth-pause' paused successfully."
    end

    test "returns 404 for non-existent pipeline", %{conn: conn} do
      conn = post(conn, ~p"/api/pipelines/nonexistent-pipeline/pause", %{"pause_cause" => "test"})
      assert json_response(conn, 404) == %{"error" => "Pipeline 'nonexistent-pipeline' not found."}
    end
  end

  describe "POST /api/pipelines/:pipeline_name/unpause" do
    test "unpauses pipeline successfully", %{conn: conn} do
      # Create an already paused pipeline
      pipeline = Repo.insert!(%Pipelines.Pipeline{
        name: "test-api-unpause",
        group: "test",
        paused: true,
        paused_by: "someone",
        pause_cause: "reason",
        paused_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      conn = post(conn, ~p"/api/pipelines/#{pipeline.name}/unpause")

      assert response = json_response(conn, 200)
      assert response["message"] == "Pipeline 'test-api-unpause' unpaused successfully."

      # Verify database state
      updated = Repo.get!(Pipelines.Pipeline, pipeline.id)
      assert updated.paused == false
      assert updated.paused_by == nil
      assert updated.pause_cause == nil
      assert updated.paused_at == nil
    end

    test "works with /go/api routing prefix", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{
        name: "test-go-api-unpause",
        group: "test",
        paused: true,
        paused_by: "someone",
        pause_cause: "reason",
        paused_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      conn = post(conn, ~p"/go/api/pipelines/#{pipeline.name}/unpause")

      assert response = json_response(conn, 200)
      assert response["message"] == "Pipeline 'test-go-api-unpause' unpaused successfully."
    end
  end

  describe "GET /api/pipelines/:pipeline_name/status" do
    test "returns the pipeline status successfully", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-status", group: "test"})

      conn = get(conn, ~p"/api/pipelines/#{pipeline.name}/status")

      assert response = json_response(conn, 200)
      assert response["paused"] == false
      assert response["paused_cause"] == ""
      assert response["paused_by"] == ""
      assert response["locked"] == false
      assert response["schedulable"] == true
    end

    test "returns locked if pipeline has a running instance", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-status-locked", group: "test", lock_behavior: "unlockWhenFinished"})
      stage = Repo.insert!(%Pipelines.Stage{name: "build", pipeline_id: pipeline.id})
      # Insert running pipeline instance and stage instance
      instance = Repo.insert!(%Pipelines.PipelineInstance{
        pipeline_id: pipeline.id,
        counter: 1,
        label: "1",
        natural_order: 1.0,
        build_cause: %{"message" => "trigger"}
      })
      Repo.insert!(%Pipelines.StageInstance{
        pipeline_instance_id: instance.id,
        name: stage.name,
        counter: 1,
        order_id: 1,
        state: "Building",
        result: "Unknown",
        approval_type: "success",
        created_time: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      conn = get(conn, ~p"/api/pipelines/#{pipeline.name}/status")

      assert response = json_response(conn, 200)
      assert response["locked"] == true
      assert response["schedulable"] == false
    end
  end

  describe "POST /api/pipelines/:pipeline_name/unlock" do
    test "unlocks pipeline successfully", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-unlock", group: "test", locked: true})

      conn = conn
      |> put_req_header("x-gocd-confirm", "true")
      |> post(~p"/api/pipelines/#{pipeline.name}/unlock")

      assert response = json_response(conn, 200)
      assert response["message"] == "Pipeline lock released for test-api-unlock."

      updated = Repo.get!(Pipelines.Pipeline, pipeline.id)
      assert updated.locked == false
    end

    test "requires X-GoCD-Confirm header", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-unlock-no-confirm", group: "test", locked: true})

      conn = post(conn, ~p"/api/pipelines/#{pipeline.name}/unlock")
      assert json_response(conn, 400) == %{"error" => "Missing required header 'X-GoCD-Confirm: true'"}
    end
  end

  describe "POST /api/pipelines/:pipeline_name/schedule" do
    test "schedules pipeline and triggers first stage", %{conn: conn} do
      # Seed pipeline config
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-schedule", group: "test"})
      material = Repo.insert!(%Pipelines.Material{type: "git", url: "https://github.com/d-led/ex_gocd", branch: "master"})
      Repo.insert_all("pipelines_materials", [%{pipeline_id: pipeline.id, material_id: material.id}])
      stage = Repo.insert!(%Pipelines.Stage{name: "build", pipeline_id: pipeline.id})
      job = Repo.insert!(%Pipelines.Job{name: "test", stage_id: stage.id})
      Repo.insert!(%Pipelines.Task{type: "exec", command: "echo", arguments: ["1"], job_id: job.id})

      # Trigger via API
      conn = post(conn, ~p"/api/pipelines/#{pipeline.name}/schedule")
      assert json_response(conn, 202) == %{"message" => "Request to schedule pipeline test-api-schedule accepted"}

      # Verify DB state
      [instance] = Repo.all(Pipelines.PipelineInstance)
      assert instance.counter == 1
      assert instance.build_cause["triggerForced"] == false

      # Check job enqueued in scheduler
      assert ExGoCD.Scheduler.pending_count() == 1
    end

    test "schedules pipeline with environment variables and materials overrides", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-schedule-overrides", group: "test"})
      material = Repo.insert!(%Pipelines.Material{type: "git", url: "https://github.com/d-led/ex_gocd", branch: "master"})
      Repo.insert_all("pipelines_materials", [%{pipeline_id: pipeline.id, material_id: material.id}])
      stage = Repo.insert!(%Pipelines.Stage{name: "build", pipeline_id: pipeline.id})
      job = Repo.insert!(%Pipelines.Job{name: "test", stage_id: stage.id})
      Repo.insert!(%Pipelines.Task{type: "exec", command: "echo", arguments: ["1"], job_id: job.id})

      fingerprint = Pipelines.material_fingerprint(material)

      params = %{
        "environment_variables" => [
          %{"name" => "OVERRIDDEN_VAR", "value" => "override_val", "secure" => false}
        ],
        "materials" => [
          %{"fingerprint" => fingerprint, "revision" => "abcdef123456"}
        ]
      }

      conn = post(conn, ~p"/api/pipelines/#{pipeline.name}/schedule", params)
      assert json_response(conn, 202) == %{"message" => "Request to schedule pipeline test-api-schedule-overrides accepted"}

      [instance] = Repo.all(Pipelines.PipelineInstance)
      assert instance.build_cause["environmentVariables"] == params["environment_variables"]

      [pmr] = Repo.all(Pipelines.PipelineMaterialRevision) |> Repo.preload(:modification)
      assert pmr.modification.revision == "abcdef123456"

      # Verify env vars are merged for execution
      [ji] = Repo.all(Pipelines.JobInstance) |> Repo.preload([stage_instance: [pipeline_instance: :pipeline], job: :tasks])
      cmd = ExGoCD.Scheduler.build_command_from_job_instance(ji)
      # Locate the export subcommand
      export_subcmd = Enum.find(cmd["subCommands"], &(&1["name"] == "export" and List.first(&1["args"]) == "OVERRIDDEN_VAR"))
      assert export_subcmd != nil
      assert List.last(export_subcmd["args"]) == "override_val"
    end
  end
end
