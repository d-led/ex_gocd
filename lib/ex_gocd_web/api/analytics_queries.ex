defmodule ExGoCDWeb.API.AnalyticsQueries do
  @moduledoc """
  The analytics questions the JSON API can ask, and the shape each answer takes.
  The controller only decides that a question was asked.

  An unknown question is answered with an error rather than a crash, because the
  caller is a UI that offers the list from `AnalyticsController.index/2`.
  """

  alias ExGoCD.Analytics

  @queries %{
    "pipeline_build_time" => :pipeline_build_time,
    "pipelines_highest_wait_time" => :pipelines_highest_wait_time,
    "all_pipelines" => :all_pipelines,
    "agent_utilization" => :agent_utilization,
    "agent_state_transition" => :agent_state_transition
  }

  @doc "The questions this module answers, by the id the API uses."
  def types, do: Map.keys(@queries)

  def run(type, params) do
    case Map.fetch(@queries, type) do
      {:ok, query} -> apply(__MODULE__, query, [params])
      :error -> %{error: "Unknown analytics type"}
    end
  end

  def pipeline_build_time(params) do
    pipeline_name = params["pipeline_name"]
    days = parse_int(params["days"] || "30")

    Analytics.pipeline_analytics(pipeline_name, days)
  end

  def pipelines_highest_wait_time(params) do
    days = parse_int(params["days"] || "7")
    limit = parse_int(params["limit"] || "10")

    %{
      pipelines: Analytics.top_pipelines_by_wait_time(days, limit)
    }
  end

  def all_pipelines(params) do
    days = parse_int(params["days"] || "7")

    %{
      pipelines: Analytics.all_pipelines_analytics(days)
    }
  end

  def agent_utilization(_params) do
    %{
      agents: Analytics.top_agents_by_utilization(10)
    }
  end

  def agent_state_transition(params) do
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

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp parse_int(int) when is_integer(int), do: int

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
