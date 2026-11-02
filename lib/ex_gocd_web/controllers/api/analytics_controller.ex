defmodule ExGoCDWeb.API.AnalyticsController do
  use ExGoCDWeb, :controller

  @doc """
  GET /api/analytics — returns available analytics types
  """
  def index(conn, _params) do
    json(conn, %{
      types: [
        %{id: "pipeline_build_time", type: "pipeline", title: "Pipeline Build Time"},
        %{
          id: "pipelines_highest_wait_time",
          type: "dashboard",
          title: "Pipelines with Highest Wait Time"
        },
        %{id: "agent_utilization", type: "dashboard", title: "Agent Utilization"},
        %{id: "agent_state_transition", type: "agent", title: "Agent State Transition"}
      ]
    })
  end

  @doc """
  GET /api/analytics/:type?id=pipeline_build_time&pipeline_name=...&start=...&end=...
  """
  def show(conn, %{"type" => type} = params) do
    result = execute_analytics(type, params)
    json(conn, result)
  end

  # ── Dispatch ───────────────────────────────────────────────────────

  defp execute_analytics(type, params), do: ExGoCDWeb.API.AnalyticsQueries.run(type, params)
end
