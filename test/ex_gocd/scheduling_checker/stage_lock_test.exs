defmodule ExGoCD.SchedulingChecker.StageLockTest do
  @moduledoc """
  Tests for the StageLock checker.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Job, Pipeline, Stage, Task}
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.StageLock

  setup do
    pipeline =
      Repo.insert!(%Pipeline{
        name: "stage-lock-#{System.unique_integer([:positive])}",
        group: "test"
      })

    stage =
      Repo.insert!(%Stage{name: "deploy", pipeline_id: pipeline.id, approval_type: "manual"})

    job = Repo.insert!(%Job{name: "deploy-job", stage_id: stage.id, resources: []})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})

    {:ok, pipeline: pipeline, stage: stage}
  end

  describe "check/3" do
    test "returns :ok when stage is not active anywhere", %{pipeline: pipeline} do
      assert StageLock.check(pipeline.name, "deploy") == :ok
    end

    test "returns {:error, :stage_locked} when stage is active in an instance", %{
      pipeline: pipeline
    } do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "deploy", "Building", "Unknown")

      assert StageLock.check(pipeline.name, "deploy") == {:error, :stage_locked}
    end

    test "returns :ok when stage is active but its stage instance ID is excluded", %{
      pipeline: pipeline
    } do
      pi = insert_instance(pipeline, 1)
      si = insert_stage(pi, "deploy", "Awaiting", "Unknown")

      assert StageLock.check(pipeline.name, "deploy", si.id) == :ok
    end

    test "returns {:error, :stage_locked} when stage is active in another instance even if one is excluded",
         %{pipeline: pipeline} do
      pi1 = insert_instance(pipeline, 1)
      si1 = insert_stage(pi1, "deploy", "Awaiting", "Unknown")

      pi2 = insert_instance(pipeline, 2)
      insert_stage(pi2, "deploy", "Building", "Unknown")

      # Excluding the Awaiting one should still find the Building one active, so it is locked
      assert StageLock.check(pipeline.name, "deploy", si1.id) == {:error, :stage_locked}
    end
  end
end
