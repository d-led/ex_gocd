defmodule ExGoCD.SchedulingChecker.ManualPipeline do
  @moduledoc """
  Blocks automatic triggers (timer, SCM poll) for pipelines whose first
  stage has `approval_type: "manual"`. Manual-only pipelines should only
  be triggered via the UI/API by an authorized user.

  Mirrors GoCD's `ManualPipelineChecker`. Used by timer trigger and
  auto-trigger paths, NOT by manual trigger (UI/API).
  """
  use ExGoCD.SchedulingChecker

  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo

  @impl true
  def check(pipeline_name) do
    pipeline = Repo.get_by(Pipeline, name: pipeline_name)

    if is_nil(pipeline) do
      {:error, :pipeline_not_found}
    else
      pipeline = Repo.preload(pipeline, stages: [])
      first_stage = Enum.min_by(pipeline.stages || [], & &1.id, fn -> nil end)

      if first_stage && first_stage.approval_type == "manual" do
        {:error, :manual_pipeline}
      else
        :ok
      end
    end
  end
end
