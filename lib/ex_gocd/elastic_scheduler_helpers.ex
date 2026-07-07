defmodule ExGoCD.ElasticSchedulerHelpers do
  @moduledoc """
  Shared helpers used by both ElasticAgentScheduler and DockerElasticAgentScheduler.
  """

  alias ExGoCD.Agents
  alias ExGoCD.Scheduler

  @doc "Returns pending in-memory jobs from the Scheduler queue."
  def get_pending_jobs do
    case Scheduler.get_queue_state() do
      %{in_memory_jobs: jobs} -> jobs
      _ -> []
    end
  rescue
    _ -> []
  end

  @doc "True if no static agent matches the job's resources."
  def needs_elastic_agent?(job) do
    resources = job[:resources] || job["resources"] || []

    matching =
      Agents.find_agents_for_job(%{resources: resources, environments: job[:environments] || []})

    Enum.empty?(matching)
  end

  @doc "Extracts a display name from a job map."
  def job_name(job) do
    job[:job] || job["job"] || "unknown"
  end

  @doc """
  Returns true if the tracked agent has been idle longer than idle_timeout_seconds.
  Also times out agents that haven't registered within 10 minutes.
  """
  def idle_too_long?(info, idle_timeout_seconds \\ 300) do
    agent_uuid = info[:agent_uuid]

    if agent_uuid do
      case Agents.get_agent_by_uuid(agent_uuid) do
        %{state: "Idle", updated_at: updated_at} ->
          idle_seconds = DateTime.diff(DateTime.utc_now(), updated_at)
          idle_seconds > idle_timeout_seconds

        _ ->
          false
      end
    else
      created_at = info[:created_at] || DateTime.utc_now()
      DateTime.diff(DateTime.utc_now(), created_at) > 600
    end
  end

  @doc "Schedules the next tick."
  def schedule_tick(tick_ms \\ 30_000) do
    Process.send_after(self(), :tick, tick_ms)
  end

  @doc "Prepends a log event, keeping at most max_events."
  def log_event(state, level, message, max_events \\ 50) do
    events =
      [%{level: level, message: message, time: DateTime.utc_now()} | state.events]
      |> Enum.take(max_events)

    %{state | events: events}
  end
end
