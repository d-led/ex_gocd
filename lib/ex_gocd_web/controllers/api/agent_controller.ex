defmodule ExGoCDWeb.API.AgentController do
  @moduledoc """
  API controller for agent registration and management.

  Implements GoCD's agent API endpoints for:
  - Agent registration
  - Agent listing and details
  - Agent updates (enable/disable, resources, environments)

  Based on GoCD API spec from api.go.cd.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Agents

  action_fallback ExGoCDWeb.FallbackController

  @doc """
  POST /api/agents/register

  Registers a new agent or updates existing agent registration.

  Expected params:
    - uuid: Agent UUID (required)
    - hostname: Agent hostname (required)
    - ipaddress: Agent IP address (required)
    - cookie: Registration cookie (optional)
  """
  def register(conn, params) do
    with {:ok, agent} <- Agents.register_agent(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/agents/#{agent.uuid}")
      |> render(:show, agent: agent)
    end
  end

  @doc """
  GET /api/agents

  Lists all agents or filters by active status.

  Query params:
    - active: "true" to show only active agents (default: false)
  """
  def index(conn, %{"active" => "true"}) do
    agents = Agents.list_active_agents()
    render(conn, :index, agents: agents)
  end

  def index(conn, _params) do
    agents = Agents.list_agents()
    render(conn, :index, agents: agents)
  end

  @doc """
  GET /api/agents/:uuid

  Gets a specific agent by UUID.
  """
  def show(conn, %{"uuid" => uuid}) do
    case Agents.get_agent_by_uuid(uuid) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found"})

      agent ->
        render(conn, :show, agent: agent)
    end
  end

  @doc """
  PATCH /api/agents/:uuid

  Updates an agent's configuration. Accepts GoCD spec fields:
  hostname, resources, environments, agent_config_state (Enabled|Disabled).
  Also accepts disabled (boolean) for compatibility.
  """
  def update(conn, %{"uuid" => uuid} = params) do
    with agent when not is_nil(agent) <- Agents.get_agent_by_uuid(uuid),
         attrs <- add_approval_cookie_if_enabling(agent, normalize_patch_params(params)),
         {:ok, updated_agent} <- Agents.update_agent(agent, attrs) do
      render(conn, :show, agent: updated_agent)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, changeset: changeset)
    end
  end

  @doc """
  DELETE /api/agents/:uuid

  Soft deletes an agent. Returns 200 with message body per GoCD API spec.
  """
  def delete(conn, %{"uuid" => uuid}) do
    with agent when not is_nil(agent) <- Agents.get_agent_by_uuid(uuid),
         {:ok, _agent} <- Agents.delete_agent(agent) do
      conn
      |> put_status(:ok)
      |> json(%{message: "Deleted 1 agent(s)."})
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not delete agent"})
    end
  end

  @doc """
  PUT /api/agents/:uuid/enable

  Enables an agent.
  """
  def enable(conn, %{"uuid" => uuid}) do
    with agent when not is_nil(agent) <- Agents.get_agent_by_uuid(uuid),
         {:ok, updated_agent} <- Agents.enable_agent(agent) do
      render(conn, :show, agent: updated_agent)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, changeset: changeset)
    end
  end

  @doc """
  PUT /api/agents/:uuid/disable

  Disables an agent.
  """
  def disable(conn, %{"uuid" => uuid}) do
    with agent when not is_nil(agent) <- Agents.get_agent_by_uuid(uuid),
         {:ok, updated_agent} <- Agents.disable_agent(agent) do
      render(conn, :show, agent: updated_agent)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, changeset: changeset)
    end
  end

  # GoCD spec uses agent_config_state (Enabled|Disabled); we store disabled (boolean).
  defp normalize_patch_params(params) do
    params
    |> Map.drop(["uuid", "controller", "action"])
    |> maybe_put_disabled_from_agent_config_state()
  end

  defp add_approval_cookie_if_enabling(agent, attrs) do
    if attrs["disabled"] == false and (is_nil(agent.cookie) or agent.cookie == "") do
      Map.put(attrs, "cookie", Agents.approval_cookie())
    else
      attrs
    end
  end

  defp maybe_put_disabled_from_agent_config_state(params) do
    case params do
      %{"agent_config_state" => "Enabled"} -> params |> Map.delete("agent_config_state") |> Map.put("disabled", false)
      %{"agent_config_state" => "Disabled"} -> params |> Map.delete("agent_config_state") |> Map.put("disabled", true)
      %{"agent_config_state" => "enabled"} -> params |> Map.delete("agent_config_state") |> Map.put("disabled", false)
      %{"agent_config_state" => "disabled"} -> params |> Map.delete("agent_config_state") |> Map.put("disabled", true)
      _ -> params
    end
  end
end
