defmodule ExGoCDWeb.API.BuildConsoleController do
  @moduledoc """
  Accepts console log chunks from agents for a given build.
  POST /api/builds/:build_id/console with body = plain text (optionally timestamp-prefixed lines).
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.AgentJobRuns

  @doc """
  POST /api/builds/:build_id/console

  Appends the request body (plain text) to the job run's console log.
  Returns 204 on success, 404 if no run found for build_id.
  """
  def append(conn, %{"build_id" => build_id}) do
    case read_body(conn) do
      {:ok, body, conn2} ->
        case AgentJobRuns.append_console(build_id, body) do
          {:ok, _run} ->
            send_resp(conn2, 204, "")

          {:error, :run_not_found} ->
            conn2
            |> put_status(404)
            |> put_view(json: ExGoCDWeb.API.BuildConsoleJSON)
            |> render(:error_404, %{})
        end
    end
  end
end
