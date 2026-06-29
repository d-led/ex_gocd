defmodule ExGoCD.SchedulingChecker.PipelineLockTest do
  @moduledoc """
  Tests for PipelineLock checker.

  Mirrors GoCD's PipelineLockChecker behavior:
  - `none`: always allows
  - `unlockWhenFinished`: blocks when any instance is Building/Awaiting
  - `lockOnFailure`: blocks when pipeline.locked == true
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Job, Pipeline, Stage, Task}
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.PipelineLock

  describe "check/1 with lock_behavior: none" do
    setup do
      pipeline =
        Repo.insert!(%Pipeline{
          name: "lock-none-#{System.unique_integer([:positive])}",
          group: "test",
          lock_behavior: "none"
        })

      {:ok, pipeline: pipeline}
    end

    test "returns :ok", %{pipeline: pipeline} do
      assert PipelineLock.check(pipeline.name) == :ok
    end
  end

  describe "check/1 with lock_behavior: unlockWhenFinished" do
    setup do
      pipeline =
        Repo.insert!(%Pipeline{
          name: "lock-uwf-#{System.unique_integer([:positive])}",
          group: "test",
          lock_behavior: "unlockWhenFinished"
        })

      stage =
        Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

      job = Repo.insert!(%Job{name: "unit", stage_id: stage.id, resources: []})
      Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})

      {:ok, pipeline: Repo.preload(pipeline, :stages)}
    end

    test "returns :ok when no instance is building", %{pipeline: pipeline} do
      assert PipelineLock.check(pipeline.name) == :ok
    end

    test "returns {:error, :pipeline_locked} when an instance is building", %{pipeline: pipeline} do
      {:ok, _instance} = ExGoCD.Pipelines.trigger_pipeline(pipeline.name)

      assert PipelineLock.check(pipeline.name) == {:error, :pipeline_locked}
    end
  end

  describe "check/1 with lock_behavior: lockOnFailure" do
    setup do
      pipeline =
        Repo.insert!(%Pipeline{
          name: "lock-lof-#{System.unique_integer([:positive])}",
          group: "test",
          lock_behavior: "lockOnFailure"
        })

      stage =
        Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

      job = Repo.insert!(%Job{name: "unit", stage_id: stage.id, resources: []})
      Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})

      {:ok, pipeline: Repo.preload(pipeline, :stages)}
    end

    test "returns :ok when pipeline is not locked", %{pipeline: pipeline} do
      assert pipeline.locked == false
      assert PipelineLock.check(pipeline.name) == :ok
    end

    test "returns {:error, :pipeline_locked} when pipeline.locked is true", %{pipeline: pipeline} do
      {:ok, pipeline} =
        pipeline |> Pipeline.changeset(%{locked: true}) |> Repo.update()

      assert PipelineLock.check(pipeline.name) == {:error, :pipeline_locked}
    end

    test "returns :ok when pipeline has active run but is not yet locked", %{pipeline: pipeline} do
      # lockOnFailure only locks AFTER failure. Active run doesn't mean locked.
      {:ok, _instance} = ExGoCD.Pipelines.trigger_pipeline(pipeline.name)

      # pipeline.locked is still false (not yet failed)
      reloaded = Repo.get!(Pipeline, pipeline.id)
      assert reloaded.locked == false
      assert PipelineLock.check(pipeline.name) == :ok
    end
  end

  describe "check/1 edge cases" do
    test "returns {:error, :pipeline_not_found} for nonexistent pipeline" do
      assert PipelineLock.check("nonexistent-pipeline-xyz") == {:error, :pipeline_not_found}
    end
  end
end
