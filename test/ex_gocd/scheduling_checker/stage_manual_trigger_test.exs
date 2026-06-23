defmodule ExGoCD.SchedulingChecker.StageManualTriggerTest do
  @moduledoc """
  Tests for the StageManualTrigger checker.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Job, Pipeline, Stage, Task}
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.StageManualTrigger

  setup do
    pipeline =
      Repo.insert!(%Pipeline{
        name: "stage-trigger-#{System.unique_integer([:positive])}",
        group: "test"
      })

    stage =
      Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

    job = Repo.insert!(%Job{name: "build-job", stage_id: stage.id, resources: []})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})

    {:ok, pipeline: pipeline, stage: stage}
  end

  describe "check/4" do
    test "returns :ok when stage is not active in the specific instance", %{pipeline: pipeline} do
      insert_instance(pipeline, 1)
      assert StageManualTrigger.check(pipeline.name, 1, "build") == :ok
    end

    test "returns {:error, :stage_already_scheduled} when stage is building/active in the instance",
         %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Building", "Unknown")

      assert StageManualTrigger.check(pipeline.name, 1, "build") ==
               {:error, :stage_already_scheduled}
    end

    test "returns :ok when stage is active but excluded", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      si = insert_stage(pi, "build", "Building", "Unknown")

      assert StageManualTrigger.check(pipeline.name, 1, "build", si.id) == :ok
    end

    test "returns :ok when stage is active in a different instance of the same pipeline", %{
      pipeline: pipeline
    } do
      pi1 = insert_instance(pipeline, 1)
      insert_stage(pi1, "build", "Building", "Unknown")

      insert_instance(pipeline, 2)

      assert StageManualTrigger.check(pipeline.name, 2, "build") == :ok
    end
  end
end
