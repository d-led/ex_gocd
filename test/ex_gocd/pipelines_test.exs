defmodule ExGoCD.PipelinesTest do
  @moduledoc """
  Tests for pipeline config and pipeline runs. Behavior-driven: trigger creates
  instances and enqueues one job per job in the stage (multiple jobs → multiple
  queue entries for multiple agents).
  """
  use ExGoCD.DataCase, async: true

  import Ecto.Query
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Job, JobInstance, Pipeline, Stage, StageInstance, Task, Template}
  alias ExGoCD.Repo

  setup do
    :ok
  end

  describe "trigger_pipeline/1" do
    test "pipeline not found returns error" do
      assert Pipelines.trigger_pipeline("nonexistent") == {:error, :pipeline_not_found}
    end

    test "trigger with single-job stage creates one instance and enqueues one job" do
      {pipeline, _stage, _job} = insert_pipeline_with_jobs("single", 1)

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.counter == 1

      [stage_instance] = from(s in ExGoCD.Pipelines.StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      job_instances = from(j in JobInstance, where: j.stage_instance_id == ^stage_instance.id) |> Repo.all()
      assert length(job_instances) == 1
      assert Enum.all?(job_instances, &(&1.state == "Scheduled"))
    end

    test "trigger with two-job stage creates two job instances and enqueues two jobs (for two agents)" do
      {pipeline, _stage, _jobs} = insert_pipeline_with_jobs("multi", 2)

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.counter == 1

      [stage_instance] = from(s in ExGoCD.Pipelines.StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      job_instances = from(j in JobInstance, where: j.stage_instance_id == ^stage_instance.id) |> Repo.all()
      assert length(job_instances) == 2, "expected 2 job instances for 2 jobs in stage"
      assert Enum.all?(job_instances, &(&1.state == "Scheduled")), "expected all jobs enqueued (Scheduled state)"
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
    end

    test "paused pipeline returns error on trigger and is not enqueued" do
      {pipeline, _stage, _job} = insert_pipeline_with_jobs("paused-pipe", 1)

      # Pause the pipeline
      assert {:ok, paused_pipe} = Pipelines.pause_pipeline(pipeline.name, "admin", "fixing build")
      assert paused_pipe.paused == true
      assert paused_pipe.paused_by == "admin"
      assert paused_pipe.pause_cause == "fixing build"
      assert paused_pipe.paused_at != nil

      # Attempt trigger — no instances created
      assert Pipelines.trigger_pipeline(pipeline.name) == {:error, :pipeline_paused}
      assert from(pi in ExGoCD.Pipelines.PipelineInstance, where: pi.pipeline_id == ^pipeline.id) |> Repo.aggregate(:count, :id) == 0

      # Unpause the pipeline
      assert {:ok, unpaused_pipe} = Pipelines.unpause_pipeline(pipeline.name)
      assert unpaused_pipe.paused == false
      assert unpaused_pipe.paused_by == nil
      assert unpaused_pipe.pause_cause == nil
      assert unpaused_pipe.paused_at == nil

      # Attempt trigger again — one instance with one scheduled job
      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.counter == 1
      [si] = from(s in ExGoCD.Pipelines.StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      [ji] = from(j in JobInstance, where: j.stage_instance_id == ^si.id) |> Repo.all()
      assert ji.state == "Scheduled"
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

  describe "templates and parameters" do
    test "pipeline with template_id resolves template stages" do
      {pipeline, %{jobs: [_job]}} = insert_pipeline_with_template("templated-pipe", "tpl-unit", 1)

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.counter == 1

      [si] = from(s in StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      assert si.name == "template-stage"

      [ji] = from(j in JobInstance, where: j.stage_instance_id == ^si.id) |> Repo.all()
      assert ji.name == "tpl-job-1"
      assert ji.state == "Scheduled"
    end

    test "template pipeline resolves template name in build command" do
      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "param-pipe", group: "test",
        label_template: "${COUNT}", parameters: %{"deploy_env" => "staging"}}))

      template = Repo.insert!(%Template{} |> Template.changeset(%{name: "param-tpl"}))
      stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "deploy", template_id: template.id, approval_type: "success"}))
      job = Repo.insert!(%Job{} |> Job.changeset(%{name: "deploy-job", stage_id: stage.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "deploy.sh", arguments: ["\#{deploy_env}"], job_id: job.id}))

      {:ok, pipeline} = pipeline |> Pipeline.changeset(%{template_id: template.id}) |> Repo.update()

      assert {:ok, _instance} = Pipelines.trigger_pipeline(pipeline.name)
    end

    test "parameters in label_template are interpolated" do
      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "label-param-pipe", group: "test",
        label_template: "release-\#{version}-${COUNT}", parameters: %{"version" => "2.0"}}))
      stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"}))
      job = Repo.insert!(%Job{} |> Job.changeset(%{name: "compiler", stage_id: stage.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "make", arguments: [], job_id: job.id}))

      Repo.preload(pipeline, [stages: [jobs: :tasks]])

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      assert instance.label == "release-2.0-1"
    end

    test "trigger options override pipeline parameters" do
      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "override-param-pipe", group: "test",
        label_template: "deploy-\#{env}-${COUNT}", parameters: %{"env" => "staging"}}))
      stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"}))
      job = Repo.insert!(%Job{} |> Job.changeset(%{name: "test", stage_id: stage.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "true", arguments: [], job_id: job.id}))

      Repo.preload(pipeline, [stages: [jobs: :tasks]])

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name, %{parameters: %{"env" => "production"}})
      assert instance.label == "deploy-production-1"
    end
  end

  describe "run_on_all_agents and run_multiple_instance" do
    test "run_on_all_agents creates one JobInstance per idle agent" do
      # Register an idle agent
      {:ok, _agent} = ExGoCD.Agents.register_agent(%{uuid: "550e8400-e29b-41d4-a716-446655441001", hostname: "host1", ipaddress: "10.0.0.1", state: "Idle"})

      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "run-all-pipe", group: "test"}))
      stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"}))
      job = Repo.insert!(%Job{} |> Job.changeset(%{name: "daemon", stage_id: stage.id, resources: [], run_on_all_agents: true}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["daemon"], job_id: job.id}))

      Repo.preload(pipeline, [stages: [jobs: :tasks]])

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      [si] = from(s in StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      job_instances = from(ji in JobInstance, where: ji.stage_instance_id == ^si.id) |> Repo.all()
      assert length(job_instances) == 1
      assert hd(job_instances).run_on_all_agents == true
    end

    test "run_multiple_instance creates N job instances" do
      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "multi-inst-pipe", group: "test"}))
      stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"}))
      job = Repo.insert!(%Job{} |> Job.changeset(%{name: "parallel", stage_id: stage.id, resources: [], run_instance_count: "3"}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["parallel"], job_id: job.id}))

      Repo.preload(pipeline, [stages: [jobs: :tasks]])

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      [si] = from(s in StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      job_instances = from(ji in JobInstance, where: ji.stage_instance_id == ^si.id) |> Repo.all()
      assert length(job_instances) == 3
      assert Enum.all?(job_instances, &(&1.run_multiple_instance == true))
      assert Enum.all?(job_instances, &(&1.name == "parallel"))
    end

    test "default job creates exactly one instance" do
      {pipeline, _stage, _jobs} = insert_pipeline_with_jobs("single-normal", 1)

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)
      [si] = from(s in StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()
      job_instances = from(ji in JobInstance, where: ji.stage_instance_id == ^si.id) |> Repo.all()
      assert length(job_instances) == 1
      assert hd(job_instances).run_on_all_agents == false
      assert hd(job_instances).run_multiple_instance == false
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
    end
  end

  defp insert_pipeline_with_template(pipeline_name, template_name, job_count) do
    template = Repo.insert!(%Template{} |> Template.changeset(%{name: template_name}))
    stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "template-stage", template_id: template.id, approval_type: "success"}))

    jobs =
      for i <- 1..job_count do
        job_name = "tpl-job-#{i}"
        job = Repo.insert!(%Job{} |> Job.changeset(%{name: job_name, stage_id: stage.id, resources: []}))
        Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: [job_name], job_id: job.id}))
        job
      end

    pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: pipeline_name, group: "test", template_id: template.id}))

    pipeline = Repo.preload(pipeline, [:materials, :template, stages: [jobs: :tasks]])

    {pipeline, %{template: template |> Repo.preload(stages: [jobs: :tasks]), stage: stage, jobs: jobs}}
  end

  describe "downstream triggering (fan-in/fan-out)" do
    test "last stage completion triggers downstream pipeline with dependency material" do
      # Create upstream pipeline
      up = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "upstream-fanout", group: "test"}))
      up_stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: up.id, approval_type: "success"}))
      up_job = Repo.insert!(%Job{} |> Job.changeset(%{name: "compile", stage_id: up_stage.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["ok"], job_id: up_job.id}))

      # Create downstream pipeline with dependency material
      down = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "downstream-fanout-recv", group: "test"}))
      Repo.insert!(%Stage{} |> Stage.changeset(%{name: "package", pipeline_id: down.id, approval_type: "success"}))
      mat = Repo.insert!(%ExGoCD.Pipelines.Material{} |> ExGoCD.Pipelines.Material.changeset(%{
        type: "dependency", url: "upstream-fanout"
      }))
      # Link material to pipeline via many_to_many
      down = Repo.preload(down, :materials)
      down
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:materials, [mat | down.materials])
      |> Repo.update!()

      # Trigger and complete upstream pipeline
      {:ok, instance} = Pipelines.trigger_pipeline("upstream-fanout")
      [si] = from(StageInstance, where: [pipeline_instance_id: ^instance.id]) |> Repo.all()
      [ji] = from(JobInstance, where: [stage_instance_id: ^si.id]) |> Repo.all()

      # Complete the job → this triggers stage completion → downstream trigger
      Pipelines.complete_job_instance(ji.id, "Passed")

      # Verify downstream was triggered
      down_instance = Repo.one(from(pi in ExGoCD.Pipelines.PipelineInstance,
        join: p in assoc(pi, :pipeline), where: p.name == "downstream-fanout-recv", order_by: [desc: pi.id], limit: 1))
      assert down_instance != nil
      assert down_instance.counter == 1
    end

    test "fan-out: one upstream triggers two downstream pipelines" do
      # Create upstream
      up = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "fanout-source", group: "test"}))
      up_stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: up.id, approval_type: "success"}))
      up_job = Repo.insert!(%Job{} |> Job.changeset(%{name: "compile", stage_id: up_stage.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["ok"], job_id: up_job.id}))

      # Create two downstreams with dependency materials
      for suffix <- ["a", "b"] do
        down = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "fanout-down-#{suffix}", group: "test"}))
        Repo.insert!(%Stage{} |> Stage.changeset(%{name: "pack", pipeline_id: down.id, approval_type: "success"}))
        mat = Repo.insert!(%ExGoCD.Pipelines.Material{} |> ExGoCD.Pipelines.Material.changeset(%{
          type: "dependency", url: "fanout-source"
        }))
        down = Repo.preload(down, :materials)
        down
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:materials, [mat | down.materials])
        |> Repo.update!()
      end

      # Trigger and complete upstream
      {:ok, instance} = Pipelines.trigger_pipeline("fanout-source")
      [si] = from(StageInstance, where: [pipeline_instance_id: ^instance.id]) |> Repo.all()
      [ji] = from(JobInstance, where: [stage_instance_id: ^si.id]) |> Repo.all()
      Pipelines.complete_job_instance(ji.id, "Passed")

      # Both downstreams triggered
      for suffix <- ["a", "b"] do
        name = "fanout-down-#{suffix}"
        inst = Repo.one(from(pi in ExGoCD.Pipelines.PipelineInstance,
          join: p in assoc(pi, :pipeline), where: p.name == ^name, order_by: [desc: pi.id], limit: 1))
        assert inst != nil, "downstream #{suffix} should be triggered"
      end
    end

    test "fan-in gate: downstream waits for ALL dependencies before triggering" do
      # Create gate pipeline that depends on BOTH dep-a AND dep-b
      gate = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "fanin-gate", group: "test"}))
      Repo.insert!(%Stage{} |> Stage.changeset(%{name: "integrate", pipeline_id: gate.id, approval_type: "success"}))
      for dep_name <- ["dep-a", "dep-b"] do
        mat = Repo.insert!(%ExGoCD.Pipelines.Material{} |> ExGoCD.Pipelines.Material.changeset(%{
          type: "dependency", url: dep_name
        }))
        gate = Repo.preload(gate, :materials)
        gate |> Ecto.Changeset.change() |> Ecto.Changeset.put_assoc(:materials, [mat | gate.materials]) |> Repo.update!()
      end

      # Create and complete dep-a
      da = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "dep-a", group: "test"}))
      da_stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: da.id, approval_type: "success"}))
      da_job = Repo.insert!(%Job{} |> Job.changeset(%{name: "compile", stage_id: da_stage.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["ok"], job_id: da_job.id}))
      {:ok, dai} = Pipelines.trigger_pipeline("dep-a")
      [da_si] = from(StageInstance, where: [pipeline_instance_id: ^dai.id]) |> Repo.all()
      [da_ji] = from(JobInstance, where: [stage_instance_id: ^da_si.id]) |> Repo.all()
      Pipelines.complete_job_instance(da_ji.id, "Passed")

      # Gate should NOT trigger yet — dep-b hasn't completed
      assert Repo.one(from(pi in ExGoCD.Pipelines.PipelineInstance,
        join: p in assoc(pi, :pipeline), where: p.name == "fanin-gate", limit: 1)) == nil

      # Create and complete dep-b
      db = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "dep-b", group: "test"}))
      db_stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: db.id, approval_type: "success"}))
      db_job = Repo.insert!(%Job{} |> Job.changeset(%{name: "compile", stage_id: db_stage.id, resources: []}))
      Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["ok"], job_id: db_job.id}))
      {:ok, dbi} = Pipelines.trigger_pipeline("dep-b")
      [db_si] = from(StageInstance, where: [pipeline_instance_id: ^dbi.id]) |> Repo.all()
      [db_ji] = from(JobInstance, where: [stage_instance_id: ^db_si.id]) |> Repo.all()
      Pipelines.complete_job_instance(db_ji.id, "Passed")

      # Now gate should trigger
      assert Repo.one(from(pi in ExGoCD.Pipelines.PipelineInstance,
        join: p in assoc(pi, :pipeline), where: p.name == "fanin-gate", limit: 1)) != nil
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
