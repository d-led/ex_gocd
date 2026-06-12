# Copyright 2026 ex_gocd
# Controller for returning server statistics (GET /api/stats and GET /go/api/stats).

defmodule ExGoCDWeb.API.StatsController do
  use ExGoCDWeb, :controller

  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Agents
  alias ExGoCD.Repo
  alias ExGoCD.Scheduler
  alias ExGoCDWeb.AgentPresence

  import Ecto.Query

  def show(conn, _params) do
    agents = Agents.list_agents()
    statuses = Enum.map(agents, &Agents.effective_status/1)

    agent_stats = %{
      total: length(agents),
      idle: Enum.count(statuses, &(&1 == :idle)),
      building: Enum.count(statuses, &(&1 == :building)),
      lost_contact: Enum.count(statuses, &(&1 == :lost_contact)),
      disabled: Enum.count(statuses, &(&1 == :disabled)),
      pending: Enum.count(statuses, &(&1 == :unknown))
    }

    # Count of active websocket connections
    active_connections = map_size(AgentPresence.list("agent"))

    running_jobs = Repo.one(
      from r in AgentJobRun,
        where: r.state != "Completed" and r.state != "Cancelled",
        select: count(r.id)
    )

    job_stats = %{
      pending: Scheduler.pending_count(),
      running: running_jobs
    }

    # System metrics
    {total_wall_clock, _} = :erlang.statistics(:wall_clock)
    uptime_seconds = div(total_wall_clock, 1000)
    memory_total_bytes = :erlang.memory(:total)

    system_stats = %{
      uptime_seconds: uptime_seconds,
      memory_total_bytes: memory_total_bytes,
      active_connections: active_connections
    }

    conn
    |> put_status(:ok)
    |> put_view(json: ExGoCDWeb.API.StatsJSON)
    |> render(:show, stats: %{agents: agent_stats, jobs: job_stats, system: system_stats})
  end
end
