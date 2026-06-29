defmodule ExGoCD.SchedulingChecker.StageActive do
  @moduledoc """
  Blocks pipeline trigger if the FIRST stage of this pipeline is currently
  Building or Awaiting (i.e., an active run is in progress).

  Mirrors GoCD's `StageActiveChecker`. Only checks the first stage,
  which is how GoCD enforces "only one instance at a time" for all pipelines.

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
      pipeline = Repo.preload(pipeline, :stages)
      first_stage = Enum.at(pipeline.stages || [], 0)

      if first_stage do
        active_count =
          from(pi in PipelineInstance,
            join: si in assoc(pi, :stage_instances),
            where:
              pi.pipeline_id == ^pipeline.id and si.name == ^first_stage.name and
                si.state in ["Building", "Awaiting"],
            select: count(si.id)
          )
          |> Repo.one()

        if active_count > 0 do
          {:error, :stage_active}
        else
          :ok
        end
      else
        :ok
      end
    end
  end
end
