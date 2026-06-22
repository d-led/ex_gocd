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
        masked = mask_secrets(body)
        case AgentJobRuns.append_console(build_id, masked) do
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
