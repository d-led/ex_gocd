# Copyright 2026 ex_gocd
# Controller for returning server version details (GET /api/version and GET /go/api/version).

defmodule ExGoCDWeb.API.VersionController do
  use ExGoCDWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:ok)
    |> put_view(json: ExGoCDWeb.API.VersionJSON)
    |> render(:show, %{})
  end
end
