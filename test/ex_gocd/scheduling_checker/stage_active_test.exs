defmodule ExGoCD.SchedulingChecker.StageActiveTest do
  @moduledoc """
  Tests for the stage-active checker.

  GoCD's StageActiveChecker only inspects the FIRST stage. If the first
  stage is Building or Awaiting, the pipeline cannot be triggered again —
  this is how GoCD enforces "only one instance at a time".
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Job, Pipeline, Stage, Task}
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.StageActive

  setup do
    pipeline =
      Repo.insert!(%Pipeline{
        name: "stage-active-test-#{System.unique_integer([:positive])}",
        group: "test"
      })

    stage =
      Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

    job = Repo.insert!(%Job{name: "unit", stage_id: stage.id, resources: []})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})

    {:ok, pipeline: pipeline, stage: stage}
  end

  describe "check/1" do
    test "returns :ok when pipeline has no instances at all", %{pipeline: pipeline} do
      assert StageActive.check(pipeline.name) == :ok
    end

    test "returns :ok when first stage is completed", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Completed", "Passed")
      assert StageActive.check(pipeline.name) == :ok
    end

    test "returns {:error, :stage_active} when first stage is Building", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Building", "Unknown")
      assert StageActive.check(pipeline.name) == {:error, :stage_active}
    end

    test "returns {:error, :stage_active} when first stage is Awaiting", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Awaiting", "Unknown")
      assert StageActive.check(pipeline.name) == {:error, :stage_active}
    end

    test "returns :ok when first stage is completed even if a later stage is Building", %{
      pipeline: pipeline
    } do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Completed", "Passed")
      insert_stage(pi, "deploy", "Building", "Unknown")
      # GoCD: only the first stage matters. Later stages don't block triggering.
      assert StageActive.check(pipeline.name) == :ok
    end

    test "returns {:error, :stage_active} when first stage is Building even if later stage is completed",
         %{
           pipeline: pipeline
         } do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Building", "Unknown")
      insert_stage(pi, "deploy", "Completed", "Passed")
      assert StageActive.check(pipeline.name) == {:error, :stage_active}
    end

    test "returns {:error, :pipeline_not_found} for nonexistent pipeline" do
      assert StageActive.check("nonexistent-pipeline-xyz") == {:error, :pipeline_not_found}
    end
  end
end
