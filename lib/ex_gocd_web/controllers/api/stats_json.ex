# Copyright 2026 ex_gocd
# JSON rendering for server statistics.

defmodule ExGoCDWeb.API.StatsJSON do
  def show(%{stats: stats}) do
    stats
  end
end
