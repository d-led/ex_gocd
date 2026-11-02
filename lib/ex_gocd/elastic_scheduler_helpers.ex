defmodule ExGoCD.ElasticSchedulerHelpers do
  @moduledoc """
  Shared helpers used by both ElasticAgentScheduler and DockerElasticAgentScheduler.
  """

  alias ExGoCD.Agents
  alias ExGoCD.Scheduler

  @doc """
  Returns all pending jobs that need an elastic agent:
  - In-memory queue jobs (from schedule_job button, etc.)
  - DB-scheduled JobInstances with state "Scheduled" that have no matching static agent
  """
  def get_pending_jobs do
    memory_jobs =
      case Scheduler.get_queue_state() do
        %{in_memory_jobs: jobs} -> jobs
        _ -> []
      end

    db_jobs = Scheduler.load_db_job_plans()

    # Only return jobs that have NO matching static agent
    (memory_jobs ++ db_jobs)
    |> Enum.filter(&needs_elastic_agent?/1)
  rescue
    _ -> []
  end

  @doc """
  True if no IDLE static agent can handle this job — meaning an elastic
  agent should be provisioned. Checks idle agents only: if all matching
  agents are busy (Building), we still scale up.

  A static agent counts as able to handle the job when the scheduler would give
  the job to it, which is the same rule the scheduler assigns by.
  """
  def needs_elastic_agent?(job) do
    Agents.list_idle_agents()
    |> Enum.all?(&(not Scheduler.job_matches_agent?(job, &1)))
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
