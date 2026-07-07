defmodule ExGoCD.AgentHealths do
  @moduledoc "Context for agent health monitoring (GoCD parity: Agent Health API)."
  import Ecto.Query, warn: false
  alias ExGoCD.{Repo, AgentHealth}

  def record_health(attrs) do
    %AgentHealth{}
    |> AgentHealth.changeset(attrs)
    |> Repo.insert()
  end

  def latest_for_agent(agent_uuid) do
    Repo.one(
      from h in AgentHealth,
        where: h.agent_uuid == ^agent_uuid,
        order_by: [desc: h.reported_at],
        limit: 1
    )
  end

  def recent_for_agent(agent_uuid, limit \\ 10) do
    Repo.all(
      from h in AgentHealth,
        where: h.agent_uuid == ^agent_uuid,
        order_by: [desc: h.reported_at],
        limit: ^limit
    )
  end

  def all_latest do
    sub =
      from h in AgentHealth,
        distinct: h.agent_uuid,
        order_by: [desc: h.reported_at]

    Repo.all(sub)
  end
end
