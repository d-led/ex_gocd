defmodule ExGoCD.SchedulingChecker.ManualPipelineTest do
  @moduledoc """
  Tests for the manual-pipeline checker.
  Behaviour-driven: given a pipeline whose first stage has approval_type
  "manual", the checker returns {:error, :manual_pipeline} to block
  automatic triggers. Pipelines with "success" first stages pass through.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Job, Pipeline, Stage, Task}
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.ManualPipeline

  setup do
    {:ok, %{}}
  end

  describe "check/1" do
    test "returns {:error, :manual_pipeline} when first stage is manual" do
      pipeline = insert_pipeline("manual-first-#{System.unique_integer([:positive])}", "manual")
      assert ManualPipeline.check(pipeline.name) == {:error, :manual_pipeline}
    end

    test "returns :ok when first stage is success" do
      pipeline = insert_pipeline("success-first-#{System.unique_integer([:positive])}", "success")
      assert ManualPipeline.check(pipeline.name) == :ok
    end

    test "returns :ok when pipeline has multiple stages but first is success" do
      pipeline =
        Repo.insert!(%Pipeline{
          name: "multi-stage-#{System.unique_integer([:positive])}",
          group: "test"
        })

      Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})
      Repo.insert!(%Stage{name: "deploy", pipeline_id: pipeline.id, approval_type: "manual"})

      assert ManualPipeline.check(pipeline.name) == :ok
    end

    test "returns {:error, :pipeline_not_found} for nonexistent pipeline" do
      assert ManualPipeline.check("nonexistent-pipeline-xyz") == {:error, :pipeline_not_found}
    end

    test "pipeline with no stages returns :ok (degenerate case)" do
      pipeline =
        Repo.insert!(%Pipeline{
          name: "no-stages-#{System.unique_integer([:positive])}",
          group: "test"
        })

      assert ManualPipeline.check(pipeline.name) == :ok
    end
  end

  defp insert_pipeline(name, approval_type) do
    pipeline = Repo.insert!(%Pipeline{name: name, group: "test"})
    stage = Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: approval_type})
    job = Repo.insert!(%Job{name: "job", stage_id: stage.id, resources: []})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["ok"], job_id: job.id})
    pipeline
  end
end
