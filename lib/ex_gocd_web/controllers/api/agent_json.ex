defmodule ExGoCDWeb.API.AgentJSON do
  @moduledoc """
  JSON rendering for agent API responses.

  Formats match GoCD's agent API response structure.
  """

  alias ExGoCD.Agents.Agent

  @doc """
  Renders a list of agents.
  """
  def index(%{agents: agents}) do
    %{
      _embedded: %{
        agents: for(agent <- agents, do: data(agent))
      }
    }
  end

  @doc """
  Renders a single agent.
  """
  def show(%{agent: agent}) do
    data(agent)
  end

  @doc """
  Renders changeset errors.
  """
  def errors(%{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)
    }
  end

  defp data(%Agent{} = agent) do
    %{
      uuid: agent.uuid,
      hostname: agent.hostname,
      # API uses snake_case
      ip_address: agent.ipaddress,
      elastic_agent_id: agent.elastic_agent_id,
      elastic_plugin_id: agent.elastic_plugin_id,
      agent_state: agent_state(agent),
      agent_config_state: agent_config_state(agent),
      # Runtime state, would come from AgentInstance
      build_state: "Idle",
      environments: agent.environments,
      resources: agent.resources,
      _links: %{
        self: %{
          href: "/api/agents/#{agent.uuid}"
        },
        doc: %{
          href: "https://api.gocd.org/current/#agents"
        }
      }
    }
  end

  defp agent_state(agent) do
    cond do
      agent.deleted -> "LostContact"
      agent.disabled -> "Disabled"
      # Would be determined by AgentInstance in real implementation
      true -> "Idle"
    end
  end

  defp agent_config_state(agent) do
    cond do
      agent.deleted -> "Unknown"
      agent.disabled -> "Disabled"
      is_nil(agent.cookie) -> "Pending"
      true -> "Enabled"
    end
  end
end
