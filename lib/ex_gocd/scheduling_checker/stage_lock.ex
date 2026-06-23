defmodule ExGoCD.SchedulingChecker.StageLock do
  @moduledoc """
  Blocks scheduling a stage if the same stage name is already active (Building/Awaiting)
  in any pipeline instance.
  """
  use ExGoCD.SchedulingChecker

  import Ecto.Query

  alias ExGoCD.Pipelines.{Pipeline, StageInstance}
  alias ExGoCD.Repo

  @impl true
  def check(_pipeline_name), do: :ok

  @doc """
  Checks if a stage is locked by an active run in any pipeline instance.
  Allows passing an optional `exclude_stage_instance_id` to prevent the stage
  under check from locking itself (e.g., during manual approval of an Awaiting stage).
  """
  @spec check(String.t(), String.t(), integer() | nil) ::
          :ok | {:error, :stage_locked | :pipeline_not_found}
  def check(pipeline_name, stage_name, exclude_stage_instance_id \\ nil)
      when is_binary(pipeline_name) and is_binary(stage_name) do
    pipeline = Repo.get_by(Pipeline, name: pipeline_name)

    if is_nil(pipeline) do
      {:error, :pipeline_not_found}
    else
      query =
        from(si in StageInstance,
          join: pi in assoc(si, :pipeline_instance),
          where:
            pi.pipeline_id == ^pipeline.id and si.name == ^stage_name and
              si.state in ["Building", "Awaiting"]
        )

      query =
        if exclude_stage_instance_id do
          from(si in query, where: si.id != ^exclude_stage_instance_id)
        else
          query
        end

      active_count = Repo.one(from(q in query, select: count(q.id)))

      if active_count > 0 do
        {:error, :stage_locked}
      else
        :ok
      end
    end
  end
end
