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

  `current_runs` maps an agent uuid to the run it is in the middle of, so a
  building agent can name its job; without it the build details are left out
  rather than sent empty.
  """
  def index(%{agents: agents} = assigns) do
    running = Map.get(assigns, :current_runs, %{})

    %{
      _links: %{
        self: %{href: "#{@api_prefix}/agents"},
        doc: %{href: @doc_url}
      },
      _embedded: %{
        agents: Enum.map(agents, &agent_data(&1, Map.get(running, &1.uuid)))
      }
    }
  end

  @doc """
  Renders a single agent (same shape as each item in _embedded.agents).
  """
  def show(%{agent: agent} = assigns) do
    agent_data(agent, Map.get(assigns, :current_run))
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

  defp agent_data(%Agent{} = agent, current_run) do
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
      build_state: build_state,
      elastic_agent_id: agent.elastic_agent_id,
      elastic_plugin_id: agent.elastic_plugin_id
    }

    case build_details(current_run) do
      nil -> base
      details -> Map.put(base, :build_details, details)
    end
  end

  # agent_config_state: Pending | Enabled | Disabled. Pending when not yet approved (no cookie).
  defp agent_config_state(%Agent{deleted: true, disabled: _}), do: "Unknown"
  defp agent_config_state(%Agent{disabled: true}), do: "Disabled"
  defp agent_config_state(%Agent{cookie: nil}), do: "Pending"
  defp agent_config_state(_), do: "Enabled"

  # agent_state: Idle | Building | LostContact | Missing | Unknown (runtime state). Never "Disabled".
  defp agent_state(%Agent{deleted: true}), do: "LostContact"

  defp agent_state(%Agent{state: s})
       when s in ["Idle", "Building", "LostContact", "Missing", "Unknown"], do: s

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

  # GoCD shows what an agent is building: the names and the three links a client
  # follows to see the job, its stage and its pipeline. No run means nothing is
  # building, whatever the agent's last report said.
  defp build_details(nil), do: nil

  defp build_details(run) do
    pipeline = encode(run.pipeline_name)
    stage = encode(run.stage_name)
    job = encode(run.job_name)

    %{
      _links: %{
        job: %{
          href:
            "#{@api_prefix}/jobs/#{pipeline}/#{run.pipeline_counter}/#{stage}/" <>
              "#{run.stage_counter}/#{job}"
        },
        stage: %{
          href:
            "#{@api_prefix}/stages/#{pipeline}/#{run.pipeline_counter}/#{stage}/" <>
              "#{run.stage_counter}"
        },
        pipeline: %{href: "#{@api_prefix}/pipelines/#{pipeline}/#{run.pipeline_counter}"}
      },
      pipeline_name: run.pipeline_name,
      stage_name: run.stage_name,
      job_name: run.job_name
    }
  end

  # A name is a path segment here, so anything not unreserved gets escaped.
  defp encode(name), do: URI.encode(name, &URI.char_unreserved?/1)
end
