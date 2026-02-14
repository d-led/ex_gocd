defmodule ExGoCD.PipelinesTest do
  @moduledoc """
  Tests for pipeline config and pipeline runs. Behavior-driven: trigger creates
  instances and enqueues one job per job in the stage (multiple jobs → multiple
  queue entries for multiple agents).
  """
  use ExGoCD.DataCase, async: false

  import Ecto.Query
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Pipeline, Stage, Job, Task, JobInstance}
  alias ExGoCD.Repo
  alias ExGoCD.Scheduler

  describe "trigger_pipeline/1" do
    test "pipeline not found returns error" do
      assert Pipelines.trigger_pipeline("nonexistent") == {:error, :pipeline_not_found}
    end

    test "trigger with single-job stage creates one instance and enqueues one job" do
      {pipeline, _stage, _job} = insert_pipeline_with_jobs("single", 1)
      n0 = Scheduler.pending_count()

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.counter == 1

      [stage_instance] = from(s in ExGoCD.Pipelines.StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      job_count = from(j in JobInstance, where: j.stage_instance_id == ^stage_instance.id) |> Repo.aggregate(:count, :id)
      assert job_count == 1
      assert Scheduler.pending_count() == n0 + 1
    end

    test "trigger with two-job stage creates two job instances and enqueues two jobs (for two agents)" do
      {pipeline, _stage, _jobs} = insert_pipeline_with_jobs("multi", 2)
      n0 = Scheduler.pending_count()

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.counter == 1

      [stage_instance] = from(s in ExGoCD.Pipelines.StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      job_count = from(j in JobInstance, where: j.stage_instance_id == ^stage_instance.id) |> Repo.aggregate(:count, :id)
      assert job_count == 2, "expected 2 job instances for 2 jobs in stage"
      assert Scheduler.pending_count() == n0 + 2, "expected 2 jobs enqueued for 2 agents"
    end
  end

  defp insert_pipeline_with_jobs(name, job_count) when job_count >= 1 do
    pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: name, group: "test"}))
    stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"}))

    jobs =
      for i <- 1..job_count do
        job_name = "job-#{i}"
        job = Repo.insert!(%Job{} |> Job.changeset(%{name: job_name, stage_id: stage.id, resources: []}))
        Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: [job_name], job_id: job.id}))
        job
      end

    pipeline = Repo.preload(pipeline, [stages: [jobs: :tasks]])
    stage = List.first(pipeline.stages)
    {pipeline, stage, jobs}
  end
end
