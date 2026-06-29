defmodule ExGoCD.SchedulingChecker.PipelinePause do
  @moduledoc """
  Blocks pipeline trigger if the pipeline is paused.

  Mirrors GoCD's `PipelinePauseChecker`.
  GoCD reference: `PipelinePauseChecker.java` in SchedulingCheckerService.
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
      if pipeline.paused do
        {:error, :pipeline_paused}
      else
        :ok
      end
    end
  end
end
