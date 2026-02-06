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
  Subscribes to agent updates for real-time notifications.
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
  Updates an agent.
  """
  @spec update_agent(Agent.t(), map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
    |> broadcast(:agent_updated)
  end

  @doc """
  Enables an agent.
  """
  @spec enable_agent(Agent.t() | String.t()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def enable_agent(%Agent{} = agent) do
    if use_mock?() do
      Mock.enable_agent(agent.uuid)
    else
      agent
      |> Agent.changeset(%{disabled: false})
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
  Soft deletes an agent.
  """
  @spec delete_agent(Agent.t() | String.t()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def delete_agent(%Agent{} = agent) do
    if use_mock?() do
      Mock.delete_agent(agent.uuid)
    else
      agent
      |> Agent.changeset(%{deleted: true})
      |> Repo.update()
      |> broadcast(:agent_deleted)
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
