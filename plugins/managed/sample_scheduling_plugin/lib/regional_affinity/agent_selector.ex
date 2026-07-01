defmodule RegionalAffinity.AgentSelector do
  @moduledoc """
  Implements ExGoCD.Plugin.AgentSelector behaviour for the regional_affinity plugin.
  Self-registers with ex_gocd's Plugin.Registry on startup.

  Uses RegionalAffinity.SchedulingDecisions for audit logging.
  """

  alias RegionalAffinity.SchedulingDecisions

  # AgentSelector callbacks (matches ExGoCD.Plugin.AgentSelector behaviour)

  def select_agent(candidates, _opts) do
    {result, reason} = do_select(candidates)
    SchedulingDecisions.record(candidates, result, reason)
    result
  end

  defp do_select([]), do: {nil, "No candidates available"}

  defp do_select(candidates) do
    # Prefer agents in the same region as this plugin node
    my_region = node_region()

    {same_region, other_regions} =
      Enum.split_with(candidates, fn a -> agent_region(a) == my_region end)

    idle_same = Enum.filter(same_region, &(&1.state == "Idle"))
    idle_other = Enum.filter(other_regions, &(&1.state == "Idle"))

    cond do
      idle_same != [] ->
        agent = pick_least_busy(idle_same)
        {"#{agent.uuid}",
         "Regional affinity: #{agent.hostname || agent.uuid} is in same region (#{my_region}), idle, least-utilized"}

      idle_other != [] ->
        agent = pick_least_busy(idle_other)
        {"#{agent.uuid}",
         "No idle agents in region #{my_region} — fell back to #{agent.hostname || agent.uuid} (#{agent_region(agent)}), least-utilized"}

      same_region != [] ->
        agent = pick_least_busy(same_region)
        {"#{agent.uuid}",
         "No idle agents — picked #{agent.hostname || agent.uuid} in same region (#{my_region}) despite state=#{agent.state}"}

      true ->
        agent = pick_least_busy(candidates)
        {"#{agent.uuid}",
         "No idle agents and none in region #{my_region} — fell back to #{agent.hostname || agent.uuid} (#{agent_region(agent)})"}
    end
  end

  defp pick_least_busy(agents) do
    # Prefer agents with fewer resources (less loaded / less specialized)
    Enum.min_by(agents, fn a -> length(Map.get(a, :resources) || []) end)
  end

  defp node_region do
    host = :inet.gethostname() |> elem(1) |> to_string()
    # Extract region from hostname pattern (e.g. "us-east-1-worker" → "us-east-1")
    case String.split(host, ".", parts: 2) do
      [region | _] -> region
      _ -> host
    end
  end

  defp agent_region(agent) do
    hostname = Map.get(agent, :hostname) || ""
    case String.split(hostname, ".", parts: 2) do
      [region | _] -> region
      _ -> hostname
    end
  rescue
    _ -> ""
  end

  # Delegate to the SchedulingDecisions GenServer for remote queries
  def decisions, do: SchedulingDecisions.decisions()
  def decisions_for(uuid), do: SchedulingDecisions.decisions_for(uuid)

  def description, do: "Regional Affinity — prefers agents in the same region"

  def ui_links do
    [{"Scheduling Decisions", "http://localhost:4100"}]
  end
end
