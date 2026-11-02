# Copyright 2026 ex_gocd
# Controller for returning server statistics (GET /api/stats and GET /go/api/stats).

defmodule ExGoCDWeb.API.StatsController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Stats
  alias ExGoCDWeb.AgentPresence

  def show(conn, _params) do
    stats = Stats.report(map_size(AgentPresence.list("agent")))

    conn
    |> put_status(:ok)
    |> put_view(json: ExGoCDWeb.API.StatsJSON)
    |> render(:show, stats: stats)
  end
end
