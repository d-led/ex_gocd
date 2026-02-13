defmodule ExGoCDWeb.API.AgentJSON do
  @moduledoc """
  JSON rendering for agent API responses.

  Response structure matches GoCD API spec (api.go.cd agents section):
  - HAL _links (self, doc, find)
  - Agent object: uuid, hostname, ip_address, sandbox, operating_system, free_space,
    agent_config_state (Pending|Enabled|Disabled), agent_state (Idle|Building|LostContact|Missing|Unknown),
    agent_version, agent_bootstrapper_version, resources, environments, build_state, build_details (when Building).
  """

  alias ExGoCD.Agents.Agent

  @api_prefix "/api"
  @doc_url "https://api.gocd.org/current/#agents"

  @doc """
  Renders list of agents per GoCD spec: _links (self, doc) and _embedded.agents[].
  """
  def index(%{agents: agents}) do
    %{
      _links: %{
        self: %{href: "#{@api_prefix}/agents"},
        doc: %{href: @doc_url}
      },
      _embedded: %{
        agents: Enum.map(agents, &agent_data/1)
      }
    }
  end

  @doc """
  Renders a single agent (same shape as each item in _embedded.agents).
  """
  def show(%{agent: agent}) do
    agent_data(agent)
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

  defp agent_data(%Agent{} = agent) do
    build_state = build_state(agent)
    base = %{
      _links: %{
        self: %{href: "#{@api_prefix}/agents/#{agent.uuid}"},
        doc: %{href: @doc_url},
        find: %{href: "#{@api_prefix}/agents/:uuid"}
      },
      uuid: agent.uuid,
      hostname: agent.hostname,
      ip_address: agent.ipaddress,
      sandbox: agent.working_dir || "",
      operating_system: agent.operating_system || "Unknown",
      free_space: agent.free_space || 0,
      agent_config_state: agent_config_state(agent),
      agent_state: agent_state(agent),
      agent_version: "20.5.0",
      agent_bootstrapper_version: "20.5.0",
      resources: agent.resources || [],
      environments: format_environments(agent.environments || []),
      build_state: build_state
    }

    if build_state == "Building" do
      Map.put(base, :build_details, build_details(agent))
    else
      base
    end
  end

  # agent_config_state: Pending | Enabled | Disabled. Pending when not yet approved (no cookie).
  defp agent_config_state(%Agent{deleted: true, disabled: _}), do: "Unknown"
  defp agent_config_state(%Agent{disabled: true}), do: "Disabled"
  defp agent_config_state(%Agent{cookie: nil}), do: "Pending"
  defp agent_config_state(_), do: "Enabled"

  # agent_state: Idle | Building | LostContact | Missing | Unknown (runtime state). Never "Disabled".
  defp agent_state(%Agent{deleted: true}), do: "LostContact"
  defp agent_state(%Agent{state: s}) when s in ["Idle", "Building", "LostContact", "Missing", "Unknown"], do: s
  defp agent_state(_), do: "Idle"

  # build_state: Idle | Building | Cancelled | Unknown.
  defp build_state(%Agent{state: "Building"}), do: "Building"
  defp build_state(%Agent{state: s}) when s in ["Idle", "Building", "Cancelled", "Unknown"], do: s
  defp build_state(_), do: "Idle"

  defp format_environments(env_names) when is_list(env_names) do
    Enum.map(env_names, fn name ->
      %{name: name, origin: %{type: "gocd"}}
    end)
  end

  defp build_details(_agent) do
    %{
      _links: %{
        job: %{href: ""},
        stage: %{href: ""},
        pipeline: %{href: ""}
      },
      pipeline_name: "",
      stage_name: "",
      job_name: ""
    }
  end
end
