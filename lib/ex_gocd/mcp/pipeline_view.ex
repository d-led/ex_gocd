defmodule ExGoCD.Mcp.PipelineView do
  @moduledoc """
  One run as a map, and as the lines a reader skims.

  A pipeline instance, a stage instance and a job instance are described here
  once because four families of tools describe them — history, one instance, one
  stage, one job — and a shape written four times drifts three times. The maps
  mirror what the instance page and the JSON API report; nothing is computed
  here that the context does not already know, except the timestamps, which are
  formatted for a reader.
  """

  alias ExGoCD.Mcp.Render
  alias ExGoCD.Pipelines.{JobInstance, PipelineInstance, StageInstance}

  @doc "A pipeline run, with its stages and their jobs."
  @spec instance(PipelineInstance.t()) :: map()
  def instance(%PipelineInstance{} = instance) do
    %{
      "name" => instance.pipeline && instance.pipeline.name,
      "counter" => instance.counter,
      "label" => instance.label,
      "scheduled_at" => Render.timestamp(instance.inserted_at),
      "status" => ExGoCD.Pipelines.pipeline_instance_status(instance),
      "trigger" => trigger(instance),
      "comment" => get_in(instance.build_cause || %{}, ["comment"]),
      "stages" => Enum.map(instance.stage_instances || [], &stage/1)
    }
  end

  @doc "A stage of a run, with its jobs."
  @spec stage(StageInstance.t()) :: map()
  def stage(%StageInstance{} = instance) do
    %{
      "name" => instance.name,
      "counter" => instance.counter,
      "state" => instance.state || "Unknown",
      "result" => instance.result || "Unknown",
      "approval_type" => instance.approval_type,
      "approved_by" => instance.approved_by,
      "cancelled_by" => instance.cancelled_by,
      "scheduled_at" => Render.timestamp(instance.scheduled_at),
      "completed_at" => Render.timestamp(instance.completed_at),
      "rerun_of_counter" => instance.rerun_of_counter,
      "jobs" => Enum.map(instance.job_instances || [], &job/1)
    }
  end

  @doc "One job of a stage."
  @spec job(JobInstance.t()) :: map()
  def job(%JobInstance{} = instance) do
    %{
      "name" => instance.name,
      "state" => instance.state || "Scheduled",
      "result" => instance.result || "Unknown",
      "agent_uuid" => instance.agent_uuid,
      "scheduled_at" => Render.timestamp(instance.scheduled_at || instance.inserted_at),
      "assigned_at" => Render.timestamp(instance.assigned_at),
      "completed_at" => Render.timestamp(instance.completed_at)
    }
  end

  @doc "The stages of a run as a table."
  @spec stage_table([StageInstance.t()]) :: String.t()
  def stage_table(stages) do
    Render.table(
      ["STAGE", "#", "STATE", "RESULT", "JOBS", "SCHEDULED", "COMPLETED"],
      Enum.map(stages, fn stage ->
        [
          stage.name,
          stage.counter,
          stage.state || "Unknown",
          stage.result || "Unknown",
          Enum.map_join(stage.job_instances || [], ", ", &job_summary/1),
          Render.timestamp(stage.scheduled_at),
          Render.timestamp(stage.completed_at)
        ]
      end)
    )
  end

  @doc "The jobs of one stage as a table."
  @spec job_table(StageInstance.t()) :: String.t()
  def job_table(%StageInstance{} = stage) do
    Render.table(
      ["JOB", "STATE", "RESULT", "AGENT", "SCHEDULED", "COMPLETED"],
      Enum.map(stage.job_instances || [], fn job ->
        [
          job.name,
          job.state || "Scheduled",
          job.result || "Unknown",
          job.agent_uuid,
          Render.timestamp(job.scheduled_at || job.inserted_at),
          Render.timestamp(job.completed_at)
        ]
      end)
    )
  end

  @doc "A run in one line: `build #12 · Passed · 2026-11-02 09:41:00Z`."
  @spec instance_line(PipelineInstance.t()) :: String.t()
  def instance_line(%PipelineInstance{} = instance) do
    "#{instance.pipeline && instance.pipeline.name} ##{instance.counter} · " <>
      "#{ExGoCD.Pipelines.pipeline_instance_status(instance)} · " <>
      "#{Render.timestamp(instance.inserted_at)}"
  end

  # What triggered a run is stored in `build_cause`, which the trigger path fills
  # in; there is no column per field.
  defp trigger(%PipelineInstance{build_cause: cause}) do
    Map.get(cause || %{}, "triggerMessage") || Map.get(cause || %{}, "trigger_message")
  end

  defp job_summary(%JobInstance{state: state, result: result} = job) do
    "#{job.name}:#{state || "Scheduled"}/#{result || "Unknown"}"
  end
end
