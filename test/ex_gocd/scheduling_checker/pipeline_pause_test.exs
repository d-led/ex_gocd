defmodule ExGoCD.SchedulingChecker.PipelinePauseTest do
  @moduledoc """
  Tests for PipelinePause checker.
  Behaviour-driven: given a paused pipeline, trigger is blocked;
  unpause it and trigger is allowed.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo
  alias ExGoCD.SchedulingChecker.PipelinePause

  setup do
    pipeline =
      Repo.insert!(%Pipeline{
        name: "pause-test-#{System.unique_integer([:positive])}",
        group: "test"
      })

    {:ok, pipeline: pipeline}
  end

  describe "check/1" do
    test "returns :ok when pipeline is not paused", %{pipeline: pipeline} do
      assert pipeline.paused == false
      assert PipelinePause.check(pipeline.name) == :ok
    end

    test "returns {:error, :pipeline_paused} when pipeline is paused", %{pipeline: pipeline} do
      {:ok, _} =
        pipeline
        |> Pipeline.changeset(%{paused: true, paused_by: "admin", pause_cause: "testing"})
        |> Repo.update()

      assert PipelinePause.check(pipeline.name) == {:error, :pipeline_paused}
    end

    test "returns {:error, :pipeline_not_found} for nonexistent pipeline" do
      assert PipelinePause.check("nonexistent-pipeline-xyz") == {:error, :pipeline_not_found}
    end
  end
end
