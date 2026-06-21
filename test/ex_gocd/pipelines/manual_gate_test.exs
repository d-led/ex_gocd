defmodule ExGoCD.Pipelines.ManualGateTest do
  @moduledoc """
  Tests for the Manual Stage Gate workflow.
  """
  use ExGoCD.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Job, JobInstance, Pipeline, Stage, StageInstance, Task}
  alias ExGoCD.Repo

  setup do
    pid = Process.whereis(ExGoCD.Scheduler)
    if pid, do: Sandbox.allow(ExGoCD.Repo, self(), pid)

    :ok
  end

  describe "manual stage gates" do
    test "completing stage 1 automatically gates stage 2 when stage 2 is manual, allows manual approval, and locks the pipeline while awaiting" do
      # Set up pipeline: stage 1 (auto) -> stage 2 (manual)
      {pipeline, stage1, stage2} = insert_pipeline_with_two_stages("manual-gate-pipe")

      # Trigger the pipeline (runs stage 1)
      {:ok, pi} = Pipelines.trigger_pipeline(pipeline.name)

      # Stage 1 instance should be building
      [si1] = Repo.all(from si in StageInstance, where: si.pipeline_instance_id == ^pi.id)
      assert si1.name == stage1.name
      assert si1.state == "Building"

      # Get job instance for stage 1
      [ji1] = Repo.all(from ji in JobInstance, where: ji.stage_instance_id == ^si1.id)
      assert ji1.state == "Scheduled"

      # Complete stage 1 job
      :ok = Pipelines.complete_job_instance(ji1.id, "Passed")

      # Stage 1 should be completed
      si1_updated = Repo.get!(StageInstance, si1.id)
      assert si1_updated.state == "Completed"
      assert si1_updated.result == "Passed"

      # Stage 2 instance should be created but in state "Awaiting"
      [si2] = Repo.all(from si in StageInstance, where: si.pipeline_instance_id == ^pi.id and si.name == ^stage2.name)
      assert si2.state == "Awaiting"
      assert si2.result == "Unknown"

      # Job instances for stage 2 should NOT be created yet
      job_instances_stage2 = Repo.all(from ji in JobInstance, where: ji.stage_instance_id == ^si2.id)
      assert Enum.empty?(job_instances_stage2)

      # Pipeline is still considered building/active, so triggering it again should fail with :pipeline_locked
      assert {:error, :pipeline_locked} == Pipelines.trigger_pipeline(pipeline.name)

      # Now manually approve stage 2
      {:ok, si2_approved} = Pipelines.approve_stage(pipeline.name, pi.counter, stage2.name)
      assert si2_approved.state == "Building"

      # Job instances for stage 2 should now be created
      [ji2] = Repo.all(from ji in JobInstance, where: ji.stage_instance_id == ^si2.id)
      assert ji2.name == "job2"
      assert ji2.state == "Scheduled"
    end
  end

  defp insert_pipeline_with_two_stages(name) do
    material = Repo.insert!(%ExGoCD.Pipelines.Material{} |> ExGoCD.Pipelines.Material.changeset(%{
      type: "git", url: "https://github.com/test/#{name}.git", branch: "main", name: "#{name}-mat"
    }))

    pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: name, group: "test", lock_behavior: "lockOnFailure"}))
    {:ok, _} = Pipelines.add_material_to_pipeline(pipeline, material)
    pipeline = Repo.preload(pipeline, :materials)

    stage1 = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "stage1", pipeline_id: pipeline.id, approval_type: "success", order_id: 1}))
    job1 = Repo.insert!(%Job{} |> Job.changeset(%{name: "job1", stage_id: stage1.id}))
    Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["1"], job_id: job1.id}))

    stage2 = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "stage2", pipeline_id: pipeline.id, approval_type: "manual", order_id: 2}))
    job2 = Repo.insert!(%Job{} |> Job.changeset(%{name: "job2", stage_id: stage2.id}))
    Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["2"], job_id: job2.id}))

    {pipeline, stage1, stage2}
  end
end
