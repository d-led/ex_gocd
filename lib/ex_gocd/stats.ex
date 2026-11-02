defmodule ExGoCD.Stats do
  @moduledoc """
  The numbers `/api/stats` publishes: agents counted by state, jobs pending and
  running, and this node's uptime and memory.

  Both the stats endpoint and the MCP server read this, so a number in an
  assistant's answer and a number in the API's are one number.

  `active_connections` is passed in rather than counted here. Live connections
  are the presence tracker's business, and a context that reached into the
  channels to count them would be one that cannot be used without a web layer.
  """

  import Ecto.Query

  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.{Agents, Repo, Scheduler}

  @doc """
  A report of this node, with the number of live agent connections the caller
  counted.
  """
  @spec report(non_neg_integer()) :: map()
  def report(active_connections)
      when is_integer(active_connections) and active_connections >= 0 do
    agents = Agents.list_agents()
    statuses = Enum.map(agents, &Agents.effective_status/1)

    %{
      agents: %{
        total: length(agents),
        idle: Enum.count(statuses, &(&1 == :idle)),
        building: Enum.count(statuses, &(&1 == :building)),
        lost_contact: Enum.count(statuses, &(&1 == :lost_contact)),
        disabled: Enum.count(statuses, &(&1 == :disabled)),
        pending: Enum.count(statuses, &(&1 == :unknown))
      },
      jobs: %{
        pending: Scheduler.pending_count(),
        running: running_jobs()
      },
      system: %{
        uptime_seconds: uptime_seconds(),
        memory_total_bytes: :erlang.memory(:total),
        active_connections: active_connections
      }
    }
  end

  defp running_jobs do
    Repo.one(
      from r in AgentJobRun,
        where: r.state != "Completed" and r.state != "Cancelled",
        select: count(r.id)
    )
  end

  # The wall clock of the whole runtime: how long this node has been up, which is
  # what a person means by uptime here.
  defp uptime_seconds do
    {total_wall_clock, _since_last_call} = :erlang.statistics(:wall_clock)
    div(total_wall_clock, 1000)
  end
end
