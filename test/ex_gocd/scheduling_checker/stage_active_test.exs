defmodule ExGoCD.SchedulingChecker.StageActiveTest do
  @moduledoc """
  Tests for the stage-active checker.
  Behaviour-driven: given a pipeline with a Building or Awaiting stage,
  trigger is blocked with :stage_active. When no stages are active,
  trigger is allowed.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Job, Pipeline, PipelineInstance, Stage, StageInstance, Task}
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.StageActive

  setup do
    pipeline =
      Repo.insert!(%Pipeline{
        name: "stage-active-test-#{System.unique_integer([:positive])}",
        group: "test"
      })

    stage = Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})
    job = Repo.insert!(%Job{name: "unit", stage_id: stage.id, resources: []})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})

    {:ok, pipeline: pipeline, stage: stage}
  end

  describe "check/1" do
    test "returns :ok when pipeline has no instances at all", %{pipeline: pipeline} do
      assert StageActive.check(pipeline.name) == :ok
    end

    test "returns :ok when pipeline has only completed stages", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Completed", "Passed")
      assert StageActive.check(pipeline.name) == :ok
    end

    test "returns {:error, :stage_active} when a stage is Building", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Building", "Unknown")
      assert StageActive.check(pipeline.name) == {:error, :stage_active}
    end

    test "returns {:error, :stage_active} when a stage is Awaiting", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Awaiting", "Unknown")
      assert StageActive.check(pipeline.name) == {:error, :stage_active}
    end

    test "returns :ok when pipeline has one completed and one Building stage (still active)", %{pipeline: pipeline} do
      pi = insert_instance(pipeline, 1)
      insert_stage(pi, "build", "Completed", "Passed")
      insert_stage(pi, "deploy", "Building", "Unknown")
      assert StageActive.check(pipeline.name) == {:error, :stage_active}
    end

    test "returns {:error, :pipeline_not_found} for nonexistent pipeline" do
      assert StageActive.check("nonexistent-pipeline-xyz") == {:error, :pipeline_not_found}
    end
  end

  defp insert_instance(pipeline, counter) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.insert!(%PipelineInstance{
      pipeline_id: pipeline.id,
      counter: counter,
      label: "#{counter}",
      natural_order: counter * 1.0,
      build_cause: %{},
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_stage(pi, name, state, result) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    counter = (Repo.aggregate(from(s in StageInstance, where: s.pipeline_instance_id == ^pi.id), :count, :id) || 0) + 1
    Repo.insert!(%StageInstance{
      pipeline_instance_id: pi.id,
      name: name,
      counter: counter,
      state: state,
      result: result,
      approval_type: "success",
      order_id: counter,
      created_time: now,
      inserted_at: now,
      updated_at: now
    })
  end
end
