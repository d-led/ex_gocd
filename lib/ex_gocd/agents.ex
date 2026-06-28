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
  require Logger

  import Ecto.Query, warn: false
  alias ExGoCD.Agents.Agent
  alias ExGoCD.Agents.Mock
  alias ExGoCD.Repo

  @agents_topic "agents:updates"
  @reg_log_table :agent_registration_log
  @max_reg_log 30

  # Check if we should use mock data
  defp use_mock? do
    System.get_env("USE_MOCK_DATA") == "true"
  end

  # ── Registration log (diagnostic: last 30 registration attempts) ────────

  @doc "Returns the last 30 registration attempts (success + failure) sorted newest first."
  def registration_log do
    try do
      :ets.tab2list(@reg_log_table)
      |> Enum.sort_by(fn {_k, _h, _r, t} -> t end, {:desc, DateTime})
    rescue
      _ -> []
    catch
      _, _ -> []
    end
  end

  # Ensure disabled=false without creating mixed atom/string key maps.
  defp ensure_disabled_false(attrs) do
    cond do
      is_map_key(attrs, "disabled") or is_map_key(attrs, :disabled) -> attrs
      is_map_key(attrs, "uuid") -> Map.put(attrs, "disabled", false)
      true -> attrs |> Map.put(:disabled, false)
    end
  end

  defp log_registration(uuid, hostname, result) do
    init_reg_log()
    logs = :ets.tab2list(@reg_log_table)
    if length(logs) >= @max_reg_log, do: :ets.delete(@reg_log_table, hd(logs))
    :ets.insert(@reg_log_table, {uuid, hostname, result, DateTime.utc_now()})
  end

  defp init_reg_log do
    case :ets.info(@reg_log_table) do
      :undefined -> :ets.new(@reg_log_table, [:named_table, :public, :set])
      _ -> :ok
    end
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

  Mirrors GoCD's AgentInstances.register():
  1. Find by UUID → update if found
  2. UUID not found → find by hostname, but only reuse if that agent
     has no different active UUID (prevents hostname collisions when
     multiple agents run on the same OS hostname).
  3. Neither found → create new agent.

  After re-registration, the agent is auto-enabled (disabled=false).
  """
  @spec register_agent(map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def register_agent(attrs) do
    if use_mock?() do
      Mock.register_agent(attrs)
    else
      do_register(attrs)
    end
  end

  defp do_register(attrs) do
    uuid = attrs["uuid"] || attrs[:uuid]
    hostname = attrs["hostname"] || attrs[:hostname]

    # GoCD parity: agents must send a UUID. If they don't, generate one
    # (convenience for dev/testing — GoCD rejects missing UUIDs).
    {uuid, attrs} =
      if is_nil(uuid) || uuid == "" do
        generated = ExGoCD.TestAgent.UUID.uuid4()
        Logger.warning("[Agents] Agent missing UUID, generated: #{generated}")

        attrs =
          if is_map_key(attrs, "uuid"),
            do: Map.put(attrs, "uuid", generated),
            else: Map.put(attrs, :uuid, generated)

        {generated, attrs}
      else
        {uuid, attrs}
      end

    result =
      case get_agent_by_uuid(uuid) do
        %Agent{} = existing_agent ->
          existing_agent
          |> Agent.changeset(ensure_disabled_false(attrs))
          |> Repo.update()
          |> broadcast(:agent_updated)

        nil ->
          register_by_hostname_or_new(attrs, hostname, uuid)
      end

    outcome = elem(result, 0)
    log_registration(uuid, hostname || "unknown", outcome)
    log_registration_audit(uuid, hostname, outcome, attrs)
    result
  end

  defp register_by_hostname_or_new(attrs, hostname, _uuid) do
    stale = find_stale_agent_by_hostname(hostname)

    if stale do
      stale
      |> Agent.changeset(ensure_disabled_false(attrs))
      |> Repo.update()
      |> broadcast(:agent_updated)
    else
      %Agent{}
      |> Agent.registration_changeset(ensure_disabled_false(attrs))
      |> Repo.insert()
      |> broadcast(:agent_registered)
    end
  end

  defp find_stale_agent_by_hostname(hostname) do
    if hostname do
      Repo.one(
        from a in Agent,
          where: a.hostname == ^hostname,
          where: a.disabled == true or a.deleted == true,
          order_by: [desc: a.updated_at],
          limit: 1
      )
    end
  end

  defp log_registration_audit(uuid, hostname, outcome, attrs) do
    ip = attrs["ipaddress"] || attrs[:ipaddress] || "unknown"
    status = if outcome == :ok, do: "success", else: "failed"
    actor = "agent:#{String.slice(uuid || "", 0, 8)}"

    ExGoCD.AuditLog.log(actor, "agent_registration",
      resource_type: "agent",
      resource_name: hostname,
      remote_ip: ip,
      details: %{uuid: uuid, status: status}
    )
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
  Soft deletes ALL disabled agents. Returns count of deleted agents.
  """
  def clean_disabled_agents do
    if use_mock?() do
      0
    else
      agents = Repo.all(from a in Agent, where: a.disabled == true and a.deleted == false)
      Enum.each(agents, fn a -> do_delete_agent(a) end)
      count = length(agents)
      ExGoCD.AuditLog.Events.agents_cleaned_disabled("admin", count)
      count
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
  Counts idle agents (state == "Idle", not disabled).
  Used by run_on_all_agents and run_multiple_instance ("all").
  """
  @spec count_idle() :: integer()
  def count_idle do
    if use_mock?() do
      Mock.list_active_agents() |> Enum.count(&(&1.state == "Idle"))
    else
      from(a in Agent, where: a.state == "Idle" and a.disabled == false and a.deleted == false)
      |> Repo.aggregate(:count, :id)
    end
  end

  @doc """
  Counts ALL agents matching the given resources (any state, not disabled/deleted).
  Mirrors GoCD's DefaultSchedulingContext.findAgentsMatching().
  Only excludes disabled/deleted agents — includes LostContact, Missing, Idle, Building.
  """
  @spec count_all_matching([String.t()]) :: integer()
  def count_all_matching([]), do: count_all()

  def count_all_matching(resources) when is_list(resources) and resources != [] do
    agents = list_all_matching(resources)
    length(agents)
  end

  def count_all_matching(_), do: count_all()

  defp count_all do
    if use_mock?() do
      length(Mock.list_active_agents())
    else
      Repo.aggregate(
        from(a in Agent, where: a.deleted == false and a.disabled == false),
        :count,
        :id
      )
    end
  end

  @doc """
  Lists ALL agents matching the given resources (any state, not disabled/deleted).
  """
  def list_all_matching(resources) when is_list(resources) and resources != [] do
    base =
      if use_mock?() do
        Mock.list_active_agents()
      else
        Repo.all(from a in Agent, where: a.deleted == false and a.disabled == false)
      end

    Enum.filter(base, fn agent ->
      agent_resources = agent.resources || []
      Enum.all?(resources, fn r -> r in agent_resources end)
    end)
  end

  def list_all_matching(_resources) do
    if use_mock?() do
      Mock.list_active_agents()
    else
      Repo.all(from a in Agent, where: a.deleted == false and a.disabled == false)
    end
  end

  @doc """
  Counts idle agents matching the given resources.
  An agent matches if its resources list contains ALL required resources.
  Used by run_on_all_agents to create one job instance per matching agent.
  """
  @spec count_idle_matching([String.t()]) :: integer()
  def count_idle_matching(resources) when is_list(resources) and resources != [] do
    idle_agents = list_idle_agents()

    Enum.count(idle_agents, fn agent ->
      agent_resources = agent.resources || []
      Enum.all?(resources, fn r -> r in agent_resources end)
    end)
  end

  def count_idle_matching(_), do: count_idle()

  @doc """
  Lists all idle (not disabled, not deleted) agents.
  """
  def list_idle_agents do
    if use_mock?() do
      Mock.list_active_agents() |> Enum.filter(&(&1.state == "Idle"))
    else
      from(a in Agent, where: a.state == "Idle" and a.disabled == false and a.deleted == false)
      |> Repo.all()
    end
  end

  @doc "Returns a map of agent_uuid => agent for the given UUIDs."
  def get_agents_by_uuids(uuids) when is_list(uuids) do
    if uuids == [] do
      %{}
    else
      from(a in Agent, where: a.uuid in ^uuids)
      |> Repo.all()
      |> Map.new(&{&1.uuid, &1})
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
  @spec effective_status(Agent.t(), keyword()) ::
          :disabled | :lost_contact | :building | :idle | :unknown
  def effective_status(agent, opts \\ [])
  def effective_status(%Agent{disabled: true}, _opts), do: :disabled

  def effective_status(agent, opts) do
    threshold_sec = Keyword.get(opts, :lost_contact_seconds, 600)

    if not use_mock?() and stale?(agent.updated_at, threshold_sec) do
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
  def touch_agent_on_heartbeat(uuid, runtime_attrs) when is_binary(uuid) do
    hostname = runtime_attrs["hostName"] || runtime_attrs["hostname"]

    result =
      uuid
      |> find_or_reregister_agent(hostname)
      |> case do
        {:ok, agent} -> update_agent_on_heartbeat(agent, runtime_attrs)
        {:error, _} = error -> error
      end

    outcome =
      case result do
        :ok -> :ok
        {:error, _} -> :error
      end

    log_registration(uuid, hostname || "unknown", outcome)
    log_registration_audit(uuid, hostname || "unknown", outcome, runtime_attrs)
    result
  end

  defp find_or_reregister_agent(uuid, hostname) do
    case get_agent_by_uuid(uuid) do
      nil ->
        if hostname do
          case Repo.get_by(Agent, hostname: hostname, disabled: false, deleted: false) do
            nil -> {:error, :not_found}
            agent -> re_assign_uuid(agent, uuid)
          end
        else
          {:error, :not_found}
        end

      agent ->
        {:ok, agent}
    end
  end

  defp re_assign_uuid(agent, uuid) do
    agent
    |> Agent.changeset(%{"uuid" => uuid})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp update_agent_on_heartbeat(agent, runtime_attrs) do
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
    old_state = agent.state
    new_state = attrs["state"] || attrs[:state]

    result =
      agent
      |> Agent.changeset(attrs)
      |> Repo.update()
      |> broadcast(:agent_updated)

    # Record state transition for analytics
    if new_state && new_state != old_state do
      ExGoCD.Analytics.record_agent_transition(agent.uuid, old_state, new_state)
    end

    result
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
      nil ->
        {:error, :not_found}

      %{disabled: true} ->
        :ok

      agent ->
        # Only mark LostContact if currently Idle/Building (just disconnected).
        # Avoids overwriting state on server restart when agent hasn't reconnected yet.
        if agent.state in ["Idle", "Building"] do
          _ = update_agent(agent, %{state: "LostContact"})
        end

        :ok
    end
  end

  @doc """
  Deletes stale/duplicate agents: deleted=true, LostContact with no elastic_id,
  and duplicate hostnames (keeping only the most recent).
  Returns count of removed agents.
  """
  @spec reap_stale_agents() :: integer()
  def reap_stale_agents do
    # Delete agents already marked as deleted
    {deleted_count, _} =
      from(a in Agent, where: a.deleted == true)
      |> Repo.delete_all()

    # Delete LostContact agents without elastic_id (probably stale)
    {lost_count, _} =
      from(a in Agent,
        where: a.state == "LostContact" and is_nil(a.elastic_agent_id)
      )
      |> Repo.delete_all()

    # Deduplicate: keep only the most recent agent per hostname
    dup_counts =
      from(a in Agent,
        group_by: a.hostname,
        having: count(a.id) > 1,
        select: {a.hostname, count(a.id)}
      )
      |> Repo.all()

    dup_removed =
      Enum.reduce(dup_counts, 0, fn {hostname, _count}, acc ->
        agents =
          from(a in Agent, where: a.hostname == ^hostname, order_by: [desc: a.updated_at])
          |> Repo.all()

        case agents do
          [_keep | to_delete] ->
            ids = Enum.map(to_delete, & &1.id)
            {removed, _} = from(a in Agent, where: a.id in ^ids) |> Repo.delete_all()
            acc + removed

          _ ->
            acc
        end
      end)

    deleted_count + lost_count + dup_removed
  end

  @doc "Deletes all k8s elastic agents. Returns {count, nil}."
  def reap_k8s_agents do
    from(a in Agent,
      where: a.elastic_plugin_id == "ex_gocd.elasticagent.kubernetes"
    )
    |> Repo.delete_all()
  end

  @doc """
  Updates an agent's runtime state (e.g. from reportCurrentStatus/reportCompleted).
  Use so the UI shows Building/Idle without waiting for the next ping.
  """
  @spec update_agent_runtime_state(String.t(), String.t()) :: :ok | {:error, :not_found}
  def update_agent_runtime_state(agent_uuid, state)
      when is_binary(agent_uuid) and is_binary(state) do
    case get_agent_by_uuid(agent_uuid) do
      nil ->
        {:error, :not_found}

      agent ->
        update_agent(agent, %{state: state})
        :ok
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

      attrs =
        if is_nil(agent.cookie) or agent.cookie == "",
          do: Map.put(attrs, :cookie, approval_cookie()),
          else: attrs

      result =
        agent
        |> Agent.changeset(attrs)
        |> Repo.update()
        |> broadcast(:agent_enabled)

      audit_agent_action(result, agent.uuid, :enabled)

      result
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
      result =
        agent
        |> Agent.changeset(%{disabled: true})
        |> Repo.update()
        |> broadcast(:agent_disabled)

      audit_agent_action(result, agent.uuid, :disabled)

      result
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
  @spec delete_agent(Agent.t() | String.t()) ::
          {:ok, Agent.t()} | {:error, Ecto.Changeset.t() | :agent_not_disabled | :not_found}
  def delete_agent(%Agent{} = agent) do
    if agent.disabled do
      result = do_delete_agent(agent)
      audit_agent_action(result, agent.uuid, :deleted)
      result
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
  Cleans up stale LostContact agents that haven't been heard from in over 24 hours.
  These accumulate when agents restart with different UUIDs after DB resets.
  Returns the count of deleted agents.
  """
  def cleanup_stale_lost_contact do
    cutoff = DateTime.add(DateTime.utc_now(), -86_400, :second)

    from(a in Agent,
      where: a.state == "LostContact" and a.updated_at < ^cutoff and a.deleted == false
    )
    |> Repo.all()
    |> Enum.reduce(0, fn agent, acc ->
      case do_delete_agent(agent) do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)
  end

  @doc """
  Bulk soft deletes agents by UUID. Only disabled agents can be deleted.
  Returns {:ok, count} or {:error, reason}.
  """
  def bulk_delete_agents(uuids) when is_list(uuids) do
    if use_mock?() do
      {:ok, Enum.count(uuids)}
    else
      agents = Repo.all(from a in Agent, where: a.uuid in ^uuids and a.deleted == false)

      enabled = Enum.filter(agents, &(not &1.disabled))

      if enabled != [] do
        {:error, "Cannot delete enabled agents: #{inspect(Enum.map(enabled, & &1.uuid))}"}
      else
        count = Enum.count(agents)
        Enum.each(agents, fn a -> do_delete_agent(a) end)
        ExGoCD.AuditLog.Events.agents_bulk_deleted("admin", count)
        {:ok, count}
      end
    end
  end

  defp audit_agent_action({:ok, _agent}, uuid, action) do
    case action do
      :enabled -> ExGoCD.AuditLog.Events.agent_enabled("admin", uuid)
      :disabled -> ExGoCD.AuditLog.Events.agent_disabled("admin", uuid)
      :deleted -> ExGoCD.AuditLog.Events.agent_deleted("admin", uuid)
    end
  end

  defp audit_agent_action(_, _, _), do: :ok

  @doc """
  Bulk enable/disable agents by UUID.
  Returns {:ok, count} or {:error, reason}.
  """
  def bulk_update_agents(uuids, disabled) when is_list(uuids) and is_boolean(disabled) do
    if use_mock?() do
      {:ok, Enum.count(uuids)}
    else
      agents = Repo.all(from a in Agent, where: a.uuid in ^uuids and a.deleted == false)
      count = Enum.count(agents)

      Enum.each(agents, fn agent ->
        {:ok, _} = update_agent(agent, %{disabled: disabled})
      end)

      {:ok, count}
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
