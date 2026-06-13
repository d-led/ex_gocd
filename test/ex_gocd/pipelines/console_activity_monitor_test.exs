# Copyright 2026 ex_gocd
# Tests for ConsoleActivityMonitor detecting hung builds.

defmodule ExGoCD.Pipelines.ConsoleActivityMonitorTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Agents
  alias ExGoCD.Pipelines.{ConsoleActivityMonitor, Job, JobInstance, Pipeline, PipelineInstance, Stage, StageInstance}
  alias ExGoCD.Repo

  @agent_uuid "550e8400-e29b-41d4-a716-446655440000"

  setup do
    # Ensure cleanup/reset
    System.put_env("EX_GOCD_DEFAULT_CONSOLE_TIMEOUT_SEC", "5")

    {:ok, _} =
      Agents.register_agent(%{
        uuid: @agent_uuid,
        hostname: "build-agent-1",
        ipaddress: "192.168.1.1"
      })

    on_exit(fn ->
      System.delete_env("EX_GOCD_DEFAULT_CONSOLE_TIMEOUT_SEC")
    end)

    :ok
  end

  describe "default console inactivity timeout" do
    test "active runs within timeout are not cancelled" do
      # Create a new run (which sets updated_at to now)
      {:ok, run} = AgentJobRuns.create_run(@agent_uuid, "build-1", "pipeline", "stage", "job")

      # Under 5 seconds default timeout: run check immediately
      ConsoleActivityMonitor.check_active_runs()

      # Run should still be active
      refetched = Repo.get!(AgentJobRun, run.id)
      assert refetched.state == "Assigned"
      assert refetched.result == nil
    end

    test "active runs exceeding timeout are cancelled" do
      {:ok, run} = AgentJobRuns.create_run(@agent_uuid, "build-2", "pipeline", "stage", "job")

      # Force updated_at back in time to simulate inactivity (e.g. 10 seconds ago)
      ten_seconds_ago = DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.truncate(:second)
      run
      |> Ecto.Changeset.change(%{updated_at: ten_seconds_ago})
      |> Repo.update!()

      ConsoleActivityMonitor.check_active_runs()

      # Run should be marked completed and cancelled
      refetched = Repo.get!(AgentJobRun, run.id)
      assert refetched.state == "Completed"
      assert refetched.result == "Cancelled"
    end
  end

  describe "custom job timeouts" do
    test "respected when numeric minutes are specified" do
      # Insert pipeline, stage, job with a 1-minute timeout (60 seconds)
      pipeline = Repo.insert!(%Pipeline{name: "pipe-custom", group: "test"})
      stage = Repo.insert!(%Stage{name: "stage-custom", pipeline_id: pipeline.id, approval_type: "success"})
      job = Repo.insert!(%Job{name: "job-custom", stage_id: stage.id, timeout: "1"}) # 1 minute = 60s

      pi = Repo.insert!(%PipelineInstance{
        pipeline_id: pipeline.id,
        counter: 1,
        label: "pipe-custom/1",
        natural_order: 1.0,
        build_cause: %{}
      })

      si = Repo.insert!(%StageInstance{
        pipeline_instance_id: pi.id,
        name: stage.name,
        counter: 1,
        order_id: 1,
        state: "Building",
        approval_type: "success",
        created_time: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      ji = Repo.insert!(%JobInstance{
        stage_instance_id: si.id,
        job_id: job.id,
        name: job.name,
        state: "Scheduled",
        scheduled_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

      {:ok, run} = AgentJobRuns.create_run(@agent_uuid, "build-custom", "pipe-custom", "stage-custom", "job-custom", job_instance_id: ji.id)

      # 1. Simulate 10s inactivity. Under 60s custom timeout, it should NOT be cancelled
      ten_seconds_ago = DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.truncate(:second)
      run
      |> Ecto.Changeset.change(%{updated_at: ten_seconds_ago})
      |> Repo.update!()

      ConsoleActivityMonitor.check_active_runs()
      refetched = Repo.get!(AgentJobRun, run.id)
      assert refetched.state == "Assigned"

      # 2. Simulate 70s inactivity. Over 60s custom timeout, it SHOULD be cancelled
      seventy_seconds_ago = DateTime.utc_now() |> DateTime.add(-70, :second) |> DateTime.truncate(:second)
      refetched
      |> Ecto.Changeset.change(%{updated_at: seventy_seconds_ago})
      |> Repo.update!()

      ConsoleActivityMonitor.check_active_runs()
      refetched = Repo.get!(AgentJobRun, run.id)
      assert refetched.state == "Completed"
      assert refetched.result == "Cancelled"
    end

    test "never cancelled when timeout is set to 'never'" do
      pipeline = Repo.insert!(%Pipeline{name: "pipe-never", group: "test"})
      stage = Repo.insert!(%Stage{name: "stage-never", pipeline_id: pipeline.id, approval_type: "success"})
      job = Repo.insert!(%Job{name: "job-never", stage_id: stage.id, timeout: "never"})

      pi = Repo.insert!(%PipelineInstance{
        pipeline_id: pipeline.id,
        counter: 1,
        label: "pipe-never/1",
        natural_order: 1.0,
        build_cause: %{}
      })

      si = Repo.insert!(%StageInstance{
        pipeline_instance_id: pi.id,
        name: stage.name,
        counter: 1,
        order_id: 1,
        state: "Building",
        approval_type: "success",
        created_time: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      ji = Repo.insert!(%JobInstance{
        stage_instance_id: si.id,
        job_id: job.id,
        name: job.name,
        state: "Scheduled",
        scheduled_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

      {:ok, run} = AgentJobRuns.create_run(@agent_uuid, "build-never", "pipe-never", "stage-never", "job-never", job_instance_id: ji.id)

      # Simulate 1 hour inactivity. With 'never' timeout, it should NOT be cancelled
      one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      run
      |> Ecto.Changeset.change(%{updated_at: one_hour_ago})
      |> Repo.update!()

      ConsoleActivityMonitor.check_active_runs()
      refetched = Repo.get!(AgentJobRun, run.id)
      assert refetched.state == "Assigned"
      assert refetched.result == nil
    end
  end

  describe "activity resets inactivity timer" do
    test "appending console logs updates updated_at and prevents cancellation" do
      {:ok, run} = AgentJobRuns.create_run(@agent_uuid, "build-activity", "pipeline", "stage", "job")

      # Force update to 10 seconds ago
      ten_seconds_ago = DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.truncate(:second)
      run
      |> Ecto.Changeset.change(%{updated_at: ten_seconds_ago})
      |> Repo.update!()

      # Simulate console write activity (resets updated_at to now)
      assert {:ok, run_updated} = AgentJobRuns.append_console("build-activity", "some activity log\n")
      # updated_at should be close to now
      assert DateTime.diff(DateTime.utc_now(), run_updated.updated_at, :second) <= 1

      # Check monitor. Elapsed time since console write is ~0s, which is under the 5s timeout.
      # It should NOT be cancelled.
      ConsoleActivityMonitor.check_active_runs()

      refetched = Repo.get!(AgentJobRun, run.id)
      assert refetched.state == "Assigned"
      assert refetched.result == nil
    end
  end
end
