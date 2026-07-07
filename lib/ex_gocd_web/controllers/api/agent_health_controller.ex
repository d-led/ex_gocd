defmodule ExGoCDWeb.API.AgentHealthController do
  @moduledoc """
  Agent health monitoring API. GoCD parity: Agent Health.

  POST /api/agent_health — agents report CPU/memory/disk metrics
  GET  /api/agent_health/:uuid — get latest health for an agent
  GET  /api/agent_health — list latest health for all agents
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.AgentHealths

  def index(conn, _params) do
    healths = AgentHealths.all_latest()
    json(conn, Enum.map(healths, &health_json/1))
  end

  def show(conn, %{"uuid" => uuid}) do
    case AgentHealths.latest_for_agent(uuid) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "No health data for agent"})
      h -> json(conn, health_json(h))
    end
  end

  def create(conn, params) do
    case AgentHealths.record_health(params) do
      {:ok, health} ->
        conn |> put_status(:created) |> json(health_json(health))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(changeset)})
    end
  end

  defp health_json(h) do
    %{
      agent_uuid: h.agent_uuid,
      cpu_percent: h.cpu_percent,
      memory_mb: h.memory_mb,
      disk_free_mb: h.disk_free_mb,
      disk_total_mb: h.disk_total_mb,
      os: h.os,
      uptime_seconds: h.uptime_seconds,
      reported_at: h.reported_at
    }
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
