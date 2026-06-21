defmodule ExGoCD.PipelinesTest do
  @moduledoc """
  Tests for pipeline config and pipeline runs. Behavior-driven: trigger creates
  instances and enqueues one job per job in the stage (multiple jobs → multiple
  queue entries for multiple agents).
  """
  use ExGoCD.DataCase, async: false

  import Ecto.Query
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Job, JobInstance, Pipeline, Stage, StageInstance, Task}
  alias ExGoCD.Repo
  alias ExGoCD.Scheduler

  setup do
    :ok
  end

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

    test "completing all jobs in first stage automatically schedules second stage" do
      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "multi-stage-pipe", group: "test"}))
      stage1 = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "stage1", pipeline_id: pipeline.id, approval_type: "success"}))
      job1 = Repo.insert!(%Job{} |> Job.changeset(%{name: "job1", stage_id: stage1.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["1"], job_id: job1.id}))

      stage2 = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "stage2", pipeline_id: pipeline.id, approval_type: "success"}))
      job2 = Repo.insert!(%Job{} |> Job.changeset(%{name: "job2", stage_id: stage2.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["2"], job_id: job2.id}))

      pipeline = Repo.preload(pipeline, [stages: [jobs: :tasks]])

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)

      [stage1_instance] = from(si in StageInstance, where: si.pipeline_instance_id == ^instance.id) |> Repo.all()
      [job1_instance] = from(ji in JobInstance, where: ji.stage_instance_id == ^stage1_instance.id) |> Repo.all()

      assert :ok = Pipelines.complete_job_instance(job1_instance.id, "Passed")

      stage1_updated = Repo.get!(StageInstance, stage1_instance.id)
      assert stage1_updated.state == "Completed"
      assert stage1_updated.result == "Passed"

      stage2_instance = from(si in StageInstance, where: si.pipeline_instance_id == ^instance.id and si.name == "stage2") |> Repo.one()
      assert stage2_instance != nil
      assert stage2_instance.state == "Building"

      [job2_instance] = from(ji in JobInstance, where: ji.stage_instance_id == ^stage2_instance.id) |> Repo.all()
      assert job2_instance.state == "Scheduled"
      assert Scheduler.pending_count() == 1
    end

    test "paused pipeline returns error on trigger and is not enqueued" do
      {pipeline, _stage, _job} = insert_pipeline_with_jobs("paused-pipe", 1)
      n0 = Scheduler.pending_count()

      # Pause the pipeline
      assert {:ok, paused_pipe} = Pipelines.pause_pipeline(pipeline.name, "admin", "fixing build")
      assert paused_pipe.paused == true
      assert paused_pipe.paused_by == "admin"
      assert paused_pipe.pause_cause == "fixing build"
      assert paused_pipe.paused_at != nil

      # Attempt trigger
      assert Pipelines.trigger_pipeline(pipeline.name) == {:error, :pipeline_paused}
      assert Scheduler.pending_count() == n0

      # Unpause the pipeline
      assert {:ok, unpaused_pipe} = Pipelines.unpause_pipeline(pipeline.name)
      assert unpaused_pipe.paused == false
      assert unpaused_pipe.paused_by == nil
      assert unpaused_pipe.pause_cause == nil
      assert unpaused_pipe.paused_at == nil

      # Attempt trigger again
      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.counter == 1
      assert Scheduler.pending_count() == n0 + 1
    end

    test "concurrency locks prevent trigger for locked pipeline" do
      {pipeline, _stage, _job} = insert_pipeline_with_jobs("locked-pipe-test", 1)

      # 1. Update pipeline to lockOnFailure
      {:ok, pipeline} = pipeline |> Pipeline.changeset(%{lock_behavior: "lockOnFailure"}) |> Repo.update()

      # 2. Trigger first run
      assert {:ok, instance1} = Pipelines.trigger_pipeline(pipeline.name)
      assert Pipelines.pipeline_building?(pipeline.id) == true
      assert Pipelines.pipeline_locked?(pipeline) == true

      # 3. Attempting to trigger again returns {:error, :pipeline_locked}
      assert Pipelines.trigger_pipeline(pipeline.name) == {:error, :pipeline_locked}

      # 4. Complete first run successfully
      [stage_instance1] = from(si in StageInstance, where: si.pipeline_instance_id == ^instance1.id) |> Repo.all()
      [job_instance1] = from(ji in JobInstance, where: ji.stage_instance_id == ^stage_instance1.id) |> Repo.all()
      assert :ok = Pipelines.complete_job_instance(job_instance1.id, "Passed")

      # 5. Since it passed, it should now be unlocked (as lockOnFailure unlocks on success)
      pipeline_reloaded = Repo.get!(Pipeline, pipeline.id)
      assert Pipelines.pipeline_building?(pipeline.id) == false
      assert Pipelines.pipeline_locked?(pipeline_reloaded) == false

      # 6. We can trigger again
      assert {:ok, instance2} = Pipelines.trigger_pipeline(pipeline.name)

      # 7. Complete second run with failure
      [stage_instance2] = from(si in StageInstance, where: si.pipeline_instance_id == ^instance2.id) |> Repo.all()
      [job_instance2] = from(ji in JobInstance, where: ji.stage_instance_id == ^stage_instance2.id) |> Repo.all()
      assert :ok = Pipelines.complete_job_instance(job_instance2.id, "Failed")

      # 8. Reload pipeline config and assert locked is true
      pipeline_reloaded = Repo.get!(Pipeline, pipeline.id)
      assert pipeline_reloaded.locked == true
      assert Pipelines.pipeline_locked?(pipeline_reloaded) == true

      # 9. Triggering again returns {:error, :pipeline_locked} even though it's not building anymore
      assert Pipelines.pipeline_building?(pipeline.id) == false
      assert Pipelines.trigger_pipeline(pipeline.name) == {:error, :pipeline_locked}

      # 10. Manual unlock allows it to trigger again
      assert {:ok, unlocked_pipe} = Pipelines.unlock_pipeline(pipeline.name)
      assert unlocked_pipe.locked == false
      assert {:ok, _instance3} = Pipelines.trigger_pipeline(pipeline.name)
    end
  end

  describe "rerun_stage/4" do
    test "rerun schedules jobs and increments stage counter" do
      {pipeline, stage, _jobs} = insert_pipeline_with_jobs("rerun-all", 2)

      # Trigger first run
      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      [stage_instance] = from(si in StageInstance, where: si.pipeline_instance_id == ^instance.id) |> Repo.all()
      assert stage_instance.counter == 1
      assert stage_instance.latest_run == true

      # Mark first job as completed and second job as failed
      [job1, job2] = from(ji in JobInstance, where: ji.stage_instance_id == ^stage_instance.id) |> Repo.all()
      assert :ok = Pipelines.complete_job_instance(job1.id, "Passed")
      assert :ok = Pipelines.complete_job_instance(job2.id, "Failed")

      # Clear the scheduler queue before testing rerun
      Scheduler.clear_queue()

      # Rerun failed jobs
      assert {:ok, new_stage} = Pipelines.rerun_stage(pipeline.name, instance.counter, stage.name, :failed)
      assert new_stage.counter == 2
      assert new_stage.latest_run == true
      assert new_stage.rerun_of_counter == 1

      # Check that original stage_instance now has latest_run == false
      prev_stage = Repo.get!(StageInstance, stage_instance.id)
      refute prev_stage.latest_run

      # Check that only failed job was scheduled (which is job-2)
      [new_job] = from(ji in JobInstance, where: ji.stage_instance_id == ^new_stage.id) |> Repo.all()
      assert new_job.name == "job-2"
      assert new_job.state == "Scheduled"
      assert Scheduler.pending_count() == 1
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
