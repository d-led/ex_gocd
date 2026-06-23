defmodule ExGoCD.SchedulingChecker.StageManualTrigger do
  @moduledoc """
  Blocks manual trigger or approval of a stage if it is already scheduled or building.
  """
  use ExGoCD.SchedulingChecker

  import Ecto.Query

  alias ExGoCD.Pipelines.{Pipeline, StageInstance}
  alias ExGoCD.Repo

  @impl true
  def check(_pipeline_name), do: :ok

  @doc """
  Checks if a stage is already scheduled or active within a specific pipeline instance.
  Allows passing an optional `exclude_stage_instance_id` to prevent self-locking.
  """
  @spec check(String.t(), integer(), String.t(), integer() | nil) ::
          :ok | {:error, :stage_already_scheduled | :pipeline_not_found}
  def check(pipeline_name, pipeline_counter, stage_name, exclude_stage_instance_id \\ nil)
      when is_binary(pipeline_name) and is_integer(pipeline_counter) and is_binary(stage_name) do
    pipeline = Repo.get_by(Pipeline, name: pipeline_name)

    if is_nil(pipeline) do
      {:error, :pipeline_not_found}
    else
      query =
        from(si in StageInstance,
          join: pi in assoc(si, :pipeline_instance),
          where:
            pi.pipeline_id == ^pipeline.id and pi.counter == ^pipeline_counter and
              si.name == ^stage_name and si.state in ["Building", "Awaiting"]
        )

      query =
        if exclude_stage_instance_id do
          from(si in query, where: si.id != ^exclude_stage_instance_id)
        else
          query
        end

      active_count = Repo.one(from(q in query, select: count(q.id)))

      if active_count > 0 do
        {:error, :stage_already_scheduled}
      else
        :ok
      end
    end
  end
end
