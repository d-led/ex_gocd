defmodule ExGoCD.SchedulingChecker.StageActive do
  @moduledoc """
  Blocks pipeline trigger if any stage of this pipeline is currently
  Building or Awaiting (i.e., an active run is in progress).

  Mirrors GoCD's `StageActiveChecker`. This is stricter than the
  lock check — it applies to ALL pipelines regardless of lock_behavior.

  GoCD reference: `StageActiveChecker.java` in SchedulingCheckerService.
  """
  use ExGoCD.SchedulingChecker

  import Ecto.Query

  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance}
  alias ExGoCD.Repo

  @impl true
  def check(pipeline_name) do
    pipeline = Repo.get_by(Pipeline, name: pipeline_name)

    if is_nil(pipeline) do
      {:error, :pipeline_not_found}
    else
      active_count =
        from(pi in PipelineInstance,
          join: si in assoc(pi, :stage_instances),
          where: pi.pipeline_id == ^pipeline.id and si.state in ["Building", "Awaiting"],
          select: count(si.id)
        )
        |> Repo.one()

      if active_count > 0 do
        {:error, :stage_active}
      else
        :ok
      end
    end
  end
end
