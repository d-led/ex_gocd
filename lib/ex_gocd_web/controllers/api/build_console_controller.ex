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
      {:ok, body, conn} ->
        append_text(conn, build_id, body)

      # The body is larger than one read, so the chunk the agent sent is larger
      # than this endpoint accepts.
      {:more, _partial, conn} ->
        answer_error(conn, :error_413, 413)

      {:error, _reason} ->
        answer_error(conn, :error_400, 400)
    end
  end

  defp append_text(conn, build_id, body) do
    case AgentJobRuns.append_console(build_id, mask_secrets(body)) do
      {:ok, _run} ->
        send_resp(conn, 204, "")

      {:error, :run_not_found} ->
        answer_error(conn, :error_404, 404)
    end
  end

  defp answer_error(conn, template, status) do
    conn
    |> put_status(status)
    |> put_view(json: ExGoCDWeb.API.BuildConsoleJSON)
    |> render(template, %{})
  end

  @mask_patterns [
    ~r/(?:TOKEN|SECRET|PASSWORD|PASS|KEY|PRIVATE_KEY)\s*[=:]\s*\S+/i,
    ~r/-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/s,
    ~r/(?:Authorization|Bearer)\s+\S+/i,
    ~r/ghp_[a-zA-Z0-9]{36}/,
    ~r/ghs_[a-zA-Z0-9]{36}/,
    ~r/xox[bprs]-[a-zA-Z0-9-]+/
  ]

  @doc false
  def mask_secrets(text) when is_binary(text) do
    Enum.reduce(@mask_patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, "******")
    end)
  end
end
