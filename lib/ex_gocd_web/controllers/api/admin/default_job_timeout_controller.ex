defmodule ExGoCDWeb.API.Admin.DefaultJobTimeoutController do
  @moduledoc """
  Default job timeout. GoCD parity:
  GET /go/api/admin/config/server/default_job_timeout.
  """
  use ExGoCDWeb, :controller

  def show(conn, _params) do
    json(conn, %{"default_job_timeout" => System.get_env("DEFAULT_JOB_TIMEOUT", "0")})
  end
end
