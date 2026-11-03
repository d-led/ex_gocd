defmodule ExGoCDWeb.API.Admin.DefaultJobTimeoutController do
  @moduledoc """
  GoCD Job Timeout Config API (`api-default-job-timeout-v1`).

  The timeout is stored here; until one is stored, `DEFAULT_JOB_TIMEOUT`
  supplies it — see `ExGoCD.ServerConfig`.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.ServerConfig

  action_fallback ExGoCDWeb.FallbackController

  @doc "GET /api/admin/config/server/default_job_timeout"
  def show(conn, _params) do
    json(conn, view(ServerConfig.default_job_timeout()))
  end

  @doc "POST and PUT /api/admin/config/server/default_job_timeout"
  def upsert(conn, params) do
    with {:ok, _setting} <- ServerConfig.update(params) do
      json(conn, view(ServerConfig.default_job_timeout()))
    end
  end

  defp view(minutes) do
    %{
      _links: %{
        doc: %{href: "https://api.gocd.org/current/#default-job-timeout"},
        self: %{href: "/api/admin/config/server/default_job_timeout"}
      },
      default_job_timeout: minutes
    }
  end
end
