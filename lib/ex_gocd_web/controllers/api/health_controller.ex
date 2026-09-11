defmodule ExGoCDWeb.API.HealthController do
  @moduledoc """
  Server health check. GoCD parity: GET /go/api/v1/health.
  """
  use ExGoCDWeb, :controller

  def show(conn, _params) do
    json(conn, %{"health" => "OK"})
  end
end
