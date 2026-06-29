defmodule RegionalAffinity.AgentSelector do
  @moduledoc """
  Implements ExGoCD.Plugin.AgentSelector behaviour for the regional_affinity plugin.
  Self-registers with ex_gocd's Plugin.Registry on startup.

  Uses RegionalAffinity.SchedulingDecisions for audit logging.
  """

  alias RegionalAffinity.SchedulingDecisions

  # AgentSelector callbacks (matches ExGoCD.Plugin.AgentSelector behaviour)

  def select_agent(candidates, _opts) do
    result = do_select(candidates)
    SchedulingDecisions.record(candidates, result)
    result
  end

  defp do_select([]), do: nil
  defp do_select([agent | _]), do: agent.uuid

  def description, do: "Regional Affinity — prefers agents in the same region"

  def ui_links do
    [{"Scheduling Decisions", "/plugins"}]
  end
end
