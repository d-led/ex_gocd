defmodule CorpPolicy do
  @moduledoc "AgentSelector: prefers least-utilized idle agents."
  def select_agent(candidates, _opts) do
    candidates
    |> Enum.reject(&(&1.state != "Idle"))
    |> Enum.sort_by(&length(&1.resources || []), :asc)
    |> List.first()
    |> case do
      nil -> nil
      agent -> agent.uuid
    end
  end

  def description, do: "Corp Policy — least-utilized idle agents"
  def ui_links, do: []
end
