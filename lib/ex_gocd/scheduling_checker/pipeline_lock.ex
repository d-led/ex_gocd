defmodule ExGoCD.SchedulingChecker.PipelineLock do
  @moduledoc """
  Blocks pipeline trigger based on the pipeline's lock_behavior.

  Mirrors GoCD's `PipelineLockChecker`:
  - `none` — always allows triggering
  - `unlockWhenFinished` — blocks if ANY instance of this pipeline is currently
    Building or Awaiting (only one instance at a time)
  - `lockOnFailure` — blocks if the pipeline's `locked` flag is true
    (set automatically on failure, cleared manually)

  GoCD reference: `PipelineLockChecker.java` in SchedulingCheckerService.
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
      case pipeline.lock_behavior do
        "none" ->
          :ok

        "unlockWhenFinished" ->
          if any_instance_building?(pipeline.id) do
            {:error, :pipeline_locked}
          else
            :ok
          end

        "lockOnFailure" ->
          if pipeline.locked do
            {:error, :pipeline_locked}
          else
            :ok
          end

        _ ->
          :ok
      end
    end
  end

  defp any_instance_building?(pipeline_id) do
    from(pi in PipelineInstance,
      join: si in assoc(pi, :stage_instances),
      where: pi.pipeline_id == ^pipeline_id and si.state in ["Building", "Awaiting"],
      select: count(pi.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end
end
