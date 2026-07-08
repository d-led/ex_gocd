defmodule ExGoCD.ConsoleActivityMonitorTest do
  @moduledoc """
  Tests for ConsoleActivityMonitor — hung job detection and cancellation.

  Covers ruby specs: HungJobServerTagTimeOut.spec, HungJobTermination.spec,
  HungJobWarning.spec, HungJobZeroTimeOutForJob.spec
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Pipelines.ConsoleActivityMonitor
  alias ExGoCD.Pipelines.{Job, JobInstance, Stage, StageInstance, Task}
  alias ExGoCD.Repo

  import ExGoCD.PipelinesFixtures,
    only: [insert_pipeline: 1, insert_pipeline_with_jobs: 2]

  @agent_uuid "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"

  setup do
    {:ok, _agent} =
      ExGoCD.Agents.register_agent(%{
        uuid: @agent_uuid,
        hostname: "test-host",
        ipaddress: "10.0.0.99",
        state: "Idle"
      })

    :ok
  end

  defp now_sec, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp ago(sec), do: DateTime.add(now_sec(), -sec, :second)

  describe "timeout detection via check_active_runs" do
    test "active run with recent updated_at is not cancelled" do
      {pipeline, stage, [_job]} = insert_pipeline_with_jobs("hung-recent", 1)
      {:ok, instance} = ExGoCD.Pipelines.trigger_pipeline(pipeline.name)
      [si] = Repo.all(from s in StageInstance, where: s.pipeline_instance_id == ^instance.id)
      [ji] = Repo.all(from j in JobInstance, where: j.stage_instance_id == ^si.id)

      {:ok, _run} =
        AgentJobRuns.create_run(@agent_uuid, "build-recent-1", pipeline.name, stage.name, "job-1",
          pipeline_counter: 1,
          stage_counter: 1,
          job_instance_id: ji.id
        )

      assert ConsoleActivityMonitor.check_active_runs() == :ok
      run = Repo.get_by!(AgentJobRun, build_id: "build-recent-1")
      refute run.result == "Cancelled"
    end

    test "active run with old updated_at is cancelled when timeout exceeded" do
      {pipeline, stage, [_job]} = insert_pipeline_with_jobs("hung-old", 1)
      {:ok, instance} = ExGoCD.Pipelines.trigger_pipeline(pipeline.name)
      [si] = Repo.all(from s in StageInstance, where: s.pipeline_instance_id == ^instance.id)
      [ji] = Repo.all(from j in JobInstance, where: j.stage_instance_id == ^si.id)
      ji |> JobInstance.changeset(%{state: "Building", result: "Unknown"}) |> Repo.update!()

      old_time = ago(1200)

      {:ok, run} =
        Repo.insert(%AgentJobRun{
          agent_uuid: @agent_uuid,
          build_id: "build-old-1",
          pipeline_name: pipeline.name,
          pipeline_counter: 1,
          stage_name: stage.name,
          stage_counter: 1,
          job_name: "job-1",
          job_instance_id: ji.id,
          state: "Building",
          updated_at: old_time
        })

      assert ConsoleActivityMonitor.check_active_runs() == :ok
      run_reloaded = Repo.get!(AgentJobRun, run.id)
      assert run_reloaded.state == "Completed"
      assert run_reloaded.result == "Cancelled"
    end
  end

  describe "job-level timeout" do
    test "job with custom timeout of 2 minutes cancels after 2 min" do
      pipeline = insert_pipeline("hung-custom-timeout")

      stage =
        Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

      job =
        Repo.insert!(%Job{
          name: "short-timeout-job",
          stage_id: stage.id,
          resources: [],
          timeout: "2"
        })

      Repo.insert!(%Task{type: "exec", command: "sleep", arguments: ["999"], job_id: job.id})

      {:ok, instance} = ExGoCD.Pipelines.trigger_pipeline(pipeline.name)
      [si] = Repo.all(from s in StageInstance, where: s.pipeline_instance_id == ^instance.id)
      [ji] = Repo.all(from j in JobInstance, where: j.stage_instance_id == ^si.id)
      ji |> JobInstance.changeset(%{state: "Building", result: "Unknown"}) |> Repo.update!()

      old_time = ago(180)

      {:ok, run} =
        Repo.insert(%AgentJobRun{
          agent_uuid: @agent_uuid,
          build_id: "build-short-timeout",
          pipeline_name: pipeline.name,
          pipeline_counter: 1,
          stage_name: "build",
          stage_counter: 1,
          job_name: "short-timeout-job",
          job_instance_id: ji.id,
          state: "Building",
          updated_at: old_time
        })

      assert ConsoleActivityMonitor.check_active_runs() == :ok
      run_reloaded = Repo.get!(AgentJobRun, run.id)
      assert run_reloaded.result == "Cancelled"
    end

    test "job with timeout 'never' is never cancelled" do
      pipeline = insert_pipeline("hung-never-timeout")

      stage =
        Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

      job =
        Repo.insert!(%Job{
          name: "never-timeout-job",
          stage_id: stage.id,
          resources: [],
          timeout: "never"
        })

      Repo.insert!(%Task{type: "exec", command: "sleep", arguments: ["999"], job_id: job.id})

      {:ok, instance} = ExGoCD.Pipelines.trigger_pipeline(pipeline.name)
      [si] = Repo.all(from s in StageInstance, where: s.pipeline_instance_id == ^instance.id)
      [ji] = Repo.all(from j in JobInstance, where: j.stage_instance_id == ^si.id)
      ji |> JobInstance.changeset(%{state: "Building", result: "Unknown"}) |> Repo.update!()

      old_time = ago(86_400)

      {:ok, run} =
        Repo.insert(%AgentJobRun{
          agent_uuid: @agent_uuid,
          build_id: "build-never",
          pipeline_name: pipeline.name,
          pipeline_counter: 1,
          stage_name: "build",
          stage_counter: 1,
          job_name: "never-timeout-job",
          job_instance_id: ji.id,
          state: "Building",
          updated_at: old_time
        })

      assert ConsoleActivityMonitor.check_active_runs() == :ok
      run_reloaded = Repo.get!(AgentJobRun, run.id)
      refute run_reloaded.result == "Cancelled"
    end
  end

  describe "state filtering" do
    test "only monitors Assigned, Building, and Completing runs" do
      {pipeline, stage, [_job]} = insert_pipeline_with_jobs("hung-state-filter", 1)
      {:ok, instance} = ExGoCD.Pipelines.trigger_pipeline(pipeline.name)
      [si] = Repo.all(from s in StageInstance, where: s.pipeline_instance_id == ^instance.id)
      [ji] = Repo.all(from j in JobInstance, where: j.stage_instance_id == ^si.id)

      old_time = ago(1200)

      {:ok, completed_run} =
        Repo.insert(%AgentJobRun{
          agent_uuid: @agent_uuid,
          build_id: "build-completed",
          pipeline_name: pipeline.name,
          pipeline_counter: 1,
          stage_name: stage.name,
          stage_counter: 1,
          job_name: "job-1",
          job_instance_id: ji.id,
          state: "Completed",
          result: "Passed",
          updated_at: old_time
        })

      assert ConsoleActivityMonitor.check_active_runs() == :ok
      completed_reloaded = Repo.get!(AgentJobRun, completed_run.id)
      assert completed_reloaded.state == "Completed"
      assert completed_reloaded.result == "Passed"
    end
  end

  describe "no active runs" do
    test "check_active_runs is safe when no runs exist" do
      assert ConsoleActivityMonitor.check_active_runs() == :ok
    end
  end
end
