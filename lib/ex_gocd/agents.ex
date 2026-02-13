defmodule ExGoCD.Agents do
  @moduledoc """
  The Agents context - manages agent configuration and lifecycle.

  This context handles persistent agent data only. Runtime state (building status,
  disk space, etc.) is managed separately by agent instances in memory.

  Based on GoCD's agent management in AgentService.java and AgentDao.java.

  ## Mock Mode

  Set `USE_MOCK_DATA=true` to use mock data instead of the database.
  This is useful for UI development without a database connection.
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.Agents.Agent
  alias ExGoCD.Agents.Mock

  @agents_topic "agents:updates"

  # Check if we should use mock data
  defp use_mock? do
    System.get_env("USE_MOCK_DATA") == "true"
  end

  @doc """
  Subscribes to agent updates (PubSub topic `agents:updates`).
  Prefer the Phoenix channel `agents:updates` for UI; this is for processes that need raw PubSub.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(ExGoCD.PubSub, @agents_topic)
  end

  defp broadcast({:ok, agent}, event) do
    Phoenix.PubSub.broadcast(ExGoCD.PubSub, @agents_topic, {event, agent})
    {:ok, agent}
  end

  defp broadcast({:error, _} = error, _event), do: error

  @doc """
  Registers a new agent or updates existing one.

  This implements GoCD's agent registration protocol where agents can re-register
  to update their configuration.
  """
  @spec register_agent(map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def register_agent(attrs) do
    if use_mock?() do
      Mock.register_agent(attrs)
    else
      uuid = attrs["uuid"] || attrs[:uuid]

      case uuid && get_agent_by_uuid(uuid) do
        nil ->
          %Agent{}
          |> Agent.registration_changeset(attrs)
          |> Repo.insert()
          |> broadcast(:agent_registered)

        existing_agent ->
          existing_agent
          |> Agent.changeset(attrs)
          |> Repo.update()
          |> broadcast(:agent_updated)
      end
    end
  end

  @doc """
  Gets a single agent by UUID.
  """
  @spec get_agent_by_uuid(String.t()) :: Agent.t() | nil
  def get_agent_by_uuid(uuid) when is_binary(uuid) do
    if use_mock?() do
      Mock.get_agent_by_uuid(uuid)
    else
      Repo.get_by(Agent, uuid: uuid)
    end
  end

  @doc """
  Gets a single agent by ID.
  """
  @spec get_agent!(integer()) :: Agent.t()
  def get_agent!(id), do: Repo.get!(Agent, id)

  @doc """
  Lists all agents (including disabled and deleted).
  """
  @spec list_agents() :: [Agent.t()]
  def list_agents do
    if use_mock?() do
      Mock.list_agents()
    else
      Repo.all(Agent)
    end
  end

  @doc """
  Lists only active agents (not disabled, not deleted).
  """
  @spec list_active_agents() :: [Agent.t()]
  def list_active_agents do
    if use_mock?() do
      Mock.list_active_agents()
    else
      from(a in Agent, where: a.disabled == false and a.deleted == false)
      |> Repo.all()
    end
  end

  @doc """
  Lists agents by environment.
  """
  @spec list_agents_in_environment(String.t()) :: [Agent.t()]
  def list_agents_in_environment(environment) do
    from(a in Agent, where: ^environment in a.environments)
    |> Repo.all()
  end

  @doc """
  Lists agents with specific resources.
  """
  @spec list_agents_with_resources([String.t()]) :: [Agent.t()]
  def list_agents_with_resources(resources) when is_list(resources) do
    from(a in Agent, where: fragment("? @> ?", a.resources, ^resources))
    |> Repo.all()
  end

  @doc """
  Effective status for display: disabled, lost_contact (no recent ping), building, idle, or unknown.
  Uses updated_at vs now to derive LostContact when no heartbeat within opts[:lost_contact_seconds].
  """
  @spec effective_status(Agent.t(), keyword()) :: :disabled | :lost_contact | :building | :idle | :unknown
  def effective_status(agent, opts \\ [])
  def effective_status(%Agent{disabled: true}, _opts), do: :disabled
  def effective_status(agent, opts) do
    threshold_sec = Keyword.get(opts, :lost_contact_seconds, 90)
    if stale?(agent.updated_at, threshold_sec) do
      :lost_contact
    else
      state_to_status(agent.state)
    end
  end

  defp stale?(nil, _), do: false
  defp stale?(updated_at, threshold_sec) do
    seconds_ago = NaiveDateTime.diff(NaiveDateTime.utc_now(), updated_at, :second)
    seconds_ago > threshold_sec
  end

  defp state_to_status("Idle"), do: :idle
  defp state_to_status("Building"), do: :building
  defp state_to_status("LostContact"), do: :lost_contact
  defp state_to_status(_), do: :unknown

  @doc """
  Updates agent runtime fields from a heartbeat/ping when the agent proves identity with its cookie.
  Prevents impersonation: if the agent has a persisted cookie (from registration), the ping must
  include the same cookie or we do not update.
  """
  @spec touch_agent_on_heartbeat(String.t(), map()) :: :ok | {:error, :not_found | :cookie_mismatch}
  def touch_agent_on_heartbeat(uuid, runtime_attrs) when is_binary(uuid) do
    case get_agent_by_uuid(uuid) do
      nil ->
        {:error, :not_found}

      agent ->
        supplied_cookie = runtime_attrs["cookie"] || runtime_attrs["Cookie"]
        if agent_identity_ok?(agent, supplied_cookie) do
          attrs =
            %{}
            |> maybe_put(:working_dir, runtime_attrs["location"])
            |> maybe_put(:free_space, parse_usable_space(runtime_attrs["usableSpace"]))
            |> maybe_put(:state, runtime_attrs["runtimeStatus"])
            |> maybe_put(:operating_system, runtime_attrs["operatingSystemName"])

          # Always update so updated_at is refreshed (avoids LostContact when agent is connected).
          attrs = if attrs == %{}, do: %{state: agent.state}, else: attrs
          update_agent(agent, attrs)
          :ok
        else
          {:error, :cookie_mismatch}
        end
    end
  end

  # When the agent has a stored cookie (from registration), the ping must supply the same cookie.
  defp agent_identity_ok?(agent, supplied_cookie) do
    case agent.cookie do
      nil -> true
      stored -> Plug.Crypto.secure_compare(to_string(stored), to_string(supplied_cookie || ""))
    end
  end

  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, key, value), do: Map.put(acc, key, value)

  defp parse_usable_space(nil), do: nil
  defp parse_usable_space(n) when is_integer(n), do: n
  defp parse_usable_space(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  @doc """
  Updates an agent.
  """
  @spec update_agent(Agent.t(), map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def update_agent(%Agent{} = agent, attrs) do
    attrs = maybe_add_approval_cookie(agent, attrs)
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
    |> broadcast(:agent_updated)
  end

  defp maybe_add_approval_cookie(agent, attrs) when is_map(attrs) do
    disabled = attrs["disabled"] || attrs[:disabled]
    if disabled == false and (is_nil(agent.cookie) or agent.cookie == "") do
      Map.put(attrs, :cookie, approval_cookie())
    else
      attrs
    end
  end

  @doc """
  Marks an agent as LostContact when the WebSocket connection is closed (channel process exits).
  Mirrors GoCD's AgentInstance.lostContact(): only updates when agent is enabled (not disabled/pending).
  Presence automatically removes the agent from the presence list; this updates DB so the UI shows LostContact.
  """
  @spec mark_lost_contact(String.t()) :: :ok | {:error, :not_found}
  def mark_lost_contact(agent_uuid) when is_binary(agent_uuid) do
    case get_agent_by_uuid(agent_uuid) do
      nil -> {:error, :not_found}
      %{disabled: true} -> :ok
      agent ->
        _ = update_agent(agent, %{state: "LostContact"})
        :ok
    end
  end

  @doc """
  Updates an agent's runtime state (e.g. from reportCurrentStatus/reportCompleted).
  Use so the UI shows Building/Idle without waiting for the next ping.
  """
  @spec update_agent_runtime_state(String.t(), String.t()) :: :ok | {:error, :not_found}
  def update_agent_runtime_state(agent_uuid, state) when is_binary(agent_uuid) and is_binary(state) do
    case get_agent_by_uuid(agent_uuid) do
      nil -> {:error, :not_found}
      agent -> _ = update_agent(agent, %{state: state}); :ok
    end
  end
  def update_agent_runtime_state(_, _), do: :ok

  @doc """
  Enables an agent. Sets a cookie when missing so API reports agent_config_state as Enabled (approved).
  """
  @spec enable_agent(Agent.t() | String.t()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def enable_agent(%Agent{} = agent) do
    if use_mock?() do
      Mock.enable_agent(agent.uuid)
    else
      attrs = %{disabled: false}
      attrs = if is_nil(agent.cookie) or agent.cookie == "", do: Map.put(attrs, :cookie, approval_cookie()), else: attrs
      agent
      |> Agent.changeset(attrs)
      |> Repo.update()
      |> broadcast(:agent_enabled)
    end
  end

  def enable_agent(uuid) when is_binary(uuid) do
    if use_mock?() do
      Mock.enable_agent(uuid)
    else
      case get_agent_by_uuid(uuid) do
        nil -> {:error, :not_found}
        agent -> enable_agent(agent)
      end
    end
  end

  @doc """
  Generates a token used when approving an agent (so agent_config_state becomes Enabled).
  """
  def approval_cookie do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  @doc """
  Disables an agent.
  """
  @spec disable_agent(Agent.t() | String.t()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def disable_agent(%Agent{} = agent) do
    if use_mock?() do
      Mock.disable_agent(agent.uuid)
    else
      agent
      |> Agent.changeset(%{disabled: true})
      |> Repo.update()
      |> broadcast(:agent_disabled)
    end
  end

  def disable_agent(uuid) when is_binary(uuid) do
    if use_mock?() do
      Mock.disable_agent(uuid)
    else
      case get_agent_by_uuid(uuid) do
        nil -> {:error, :not_found}
        agent -> disable_agent(agent)
      end
    end
  end

  @doc """
  Soft deletes an agent. Fails unless the agent is disabled (matches GoCD: delete only after disable).
  """
  @spec delete_agent(Agent.t() | String.t()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t() | :agent_not_disabled | :not_found}
  def delete_agent(%Agent{} = agent) do
    if agent.disabled do
      do_delete_agent(agent)
    else
      {:error, :agent_not_disabled}
    end
  end

  def delete_agent(uuid) when is_binary(uuid) do
    if use_mock?() do
      Mock.delete_agent(uuid)
    else
      case get_agent_by_uuid(uuid) do
        nil -> {:error, :not_found}
        agent -> delete_agent(agent)
      end
    end
  end

  defp do_delete_agent(agent) do
    if use_mock?() do
      Mock.delete_agent(agent.uuid)
    else
      agent
      |> Agent.changeset(%{deleted: true})
      |> Repo.update()
      |> broadcast(:agent_deleted)
    end
  end

  @doc """
  Adds resources to an agent.
  """
  @spec add_resources(Agent.t(), [String.t()]) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def add_resources(%Agent{} = agent, new_resources) do
    agent = Repo.reload(agent)
    updated_resources = (agent.resources ++ new_resources) |> Enum.uniq()
    update_agent(agent, %{resources: updated_resources})
  end

  @doc """
  Removes resources from an agent.
  """
  @spec remove_resources(Agent.t(), [String.t()]) ::
          {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def remove_resources(%Agent{} = agent, resources_to_remove) do
    agent = Repo.reload(agent)
    updated_resources = agent.resources -- resources_to_remove
    update_agent(agent, %{resources: updated_resources})
  end

  @doc """
  Adds agent to environments.
  """
  @spec add_environments(Agent.t(), [String.t()]) ::
          {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def add_environments(%Agent{} = agent, new_envs) do
    agent = Repo.reload(agent)
    updated_envs = (agent.environments ++ new_envs) |> Enum.uniq()
    update_agent(agent, %{environments: updated_envs})
  end

  @doc """
  Removes agent from environments.
  """
  @spec remove_environments(Agent.t(), [String.t()]) ::
          {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def remove_environments(%Agent{} = agent, envs_to_remove) do
    agent = Repo.reload(agent)
    updated_envs = agent.environments -- envs_to_remove
    update_agent(agent, %{environments: updated_envs})
  end

  @doc """
  Finds agents capable of running a job (matching resources and environments).
  """
  @spec find_agents_for_job(map()) :: [Agent.t()]
  def find_agents_for_job(%{resources: required_resources, environment: job_environment}) do
    list_active_agents()
    |> Enum.filter(fn agent ->
      # Agent must have all required resources
      # Agent must be in the job's environment (or job has no environment)
      Agent.has_all_resources?(agent, required_resources) and
        (is_nil(job_environment) or Agent.in_environment?(agent, job_environment))
    end)
  end

  def find_agents_for_job(%{resources: required_resources}) do
    list_active_agents()
    |> Enum.filter(&Agent.has_all_resources?(&1, required_resources))
  end
end
