defmodule ExGoCD.SchedulingChecker.PipelineActive do
  @moduledoc """
  Blocks pipeline scheduling/rerunning if a pipeline instance is active.
  For rerun-stage, it prevents triggering a stage on a pipeline instance
  that is currently executing.
  """
  use ExGoCD.SchedulingChecker

  import Ecto.Query

  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance}
  alias ExGoCD.Repo

  @impl true
  def check(pipeline_name) do
    # Default to StageActive's check if only name is provided
    ExGoCD.SchedulingChecker.StageActive.check(pipeline_name)
  end

  @doc """
  Checks if a specific pipeline instance has active stages.
  """
  @spec check(String.t(), integer()) :: :ok | {:error, :pipeline_active | :pipeline_not_found}
  def check(pipeline_name, pipeline_counter)
      when is_binary(pipeline_name) and is_integer(pipeline_counter) do
    pipeline = Repo.get_by(Pipeline, name: pipeline_name)

    if is_nil(pipeline) do
      {:error, :pipeline_not_found}
    else
      active_count =
        from(pi in PipelineInstance,
          join: si in assoc(pi, :stage_instances),
          where:
            pi.pipeline_id == ^pipeline.id and pi.counter == ^pipeline_counter and
              si.state in ["Building", "Awaiting"],
          select: count(si.id)
        )
        |> Repo.one()

      if active_count > 0 do
        {:error, :pipeline_active}
      else
        :ok
      end
    end
  end
end
