defmodule ExGoCD.SchedulingChecker.PipelineActiveTest do
  @moduledoc """
  Tests for the PipelineActive checker.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Job, Pipeline, Stage, Task}
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.PipelineActive

  setup do
    pipeline =
      Repo.insert!(%Pipeline{
        name: "pipe-active-#{System.unique_integer([:positive])}",
        group: "test"
      })

    stage =
      Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

    job = Repo.insert!(%Job{name: "unit", stage_id: stage.id, resources: []})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})

    {:ok, pipeline: pipeline, stage: stage}
  end

  describe "check/2" do
    test "returns :ok when pipeline instance has only completed stages", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Completed", "Passed")
      assert PipelineActive.check(pipeline.name, 1) == :ok
    end

    test "returns {:error, :pipeline_active} when a stage in the specific instance is Building",
         %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Building", "Unknown")
      assert PipelineActive.check(pipeline.name, 1) == {:error, :pipeline_active}
    end

    test "returns :ok when another instance of the same pipeline is Building but this instance is completed",
         %{pipeline: pipeline} do
      pi1 = insert_instance(pipeline, 1)
      insert_stage(pi1, "build", "Completed", "Passed")

      pi2 = insert_instance(pipeline, 2)
      insert_stage(pi2, "build", "Building", "Unknown")

      assert PipelineActive.check(pipeline.name, 1) == :ok
      assert PipelineActive.check(pipeline.name, 2) == {:error, :pipeline_active}
    end

    test "returns {:error, :pipeline_not_found} for nonexistent pipeline" do
      assert PipelineActive.check("nonexistent", 1) == {:error, :pipeline_not_found}
    end
  end
end
