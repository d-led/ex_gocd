defmodule ExGoCDWeb.API.AnalyticsController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Analytics

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

  defp execute_analytics("pipeline_build_time", params) do
    pipeline_name = params["pipeline_name"]
    days = parse_int(params["days"] || "30")

    Analytics.pipeline_analytics(pipeline_name, days)
  end

  defp execute_analytics("pipelines_highest_wait_time", params) do
    days = parse_int(params["days"] || "7")
    limit = parse_int(params["limit"] || "10")

    %{
      pipelines: Analytics.top_pipelines_by_wait_time(days, limit)
    }
  end

  defp execute_analytics("all_pipelines", params) do
    days = parse_int(params["days"] || "7")

    %{
      pipelines: Analytics.all_pipelines_analytics(days)
    }
  end

  defp execute_analytics("agent_utilization", _params) do
    %{
      agents: Analytics.top_agents_by_utilization(10)
    }
  end

  defp execute_analytics("agent_state_transition", params) do
    agent_uuid = params["agent_uuid"]

    start_dt =
      parse_datetime(params["start"]) || DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)

    end_dt = parse_datetime(params["end"]) || DateTime.utc_now()

    transitions = Analytics.agent_transitions(agent_uuid, start_dt, end_dt)

    %{
      agent_uuid: agent_uuid,
      transitions:
        Enum.map(transitions, fn t ->
          %{
            from_state: t.from_state,
            to_state: t.to_state,
            transitioned_at: t.transitioned_at
          }
        end),
      utilization: Analytics.agent_utilization(agent_uuid, start_dt, end_dt)
    }
  end

  defp execute_analytics(_, _params) do
    %{error: "Unknown analytics type"}
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
