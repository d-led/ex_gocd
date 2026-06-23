defmodule ExGoCDWeb.AgentRemotingController do
  @moduledoc """
  HTTP controller implementing GoCD's internal agent remoting API.

  The official GoCD Go agent communicates via HTTP POST to `/remoting/api/agent/*`
  endpoints (ping, get_work, get_cookie, report_current_status, etc.).
  This controller provides backward-compatible HTTP endpoints so the real Go agent
  can communicate with our Elixir rewrite.

  Based on GoCD's InternalAgentControllerV1.java.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents
  alias ExGoCD.Scheduler

  @doc """
  POST /remoting/api/agent/ping

  Heartbeat from the agent. Updates runtime info and checks for idle work assignment.
  The Go agent sends `{"agentRuntimeInfo": {...}}` and expects an AgentInstruction response.
  """
  def ping(conn, _params) do
    with {:ok, body} <- read_json_body(conn),
         uuid <- extract_uuid(body),
         :ok <- verify_agent_identity(conn, uuid) do
      runtime_info = body["agentRuntimeInfo"] || body
      _ = Agents.touch_agent_on_heartbeat(uuid, flatten_runtime_info(runtime_info))

      if runtime_status(runtime_info) == "Idle" do
        _ = Scheduler.try_assign_work(uuid)
      end

      json(conn, %{"agentInstruction" => "NONE"})
    end
  end

  @doc """
  POST /remoting/api/agent/get_work

  Agent polls for assigned work. Returns NoWork when nothing is queued.
  """
  def get_work(conn, _params) do
    with {:ok, body} <- read_json_body(conn),
         uuid <- extract_uuid(body),
         :ok <- verify_agent_identity(conn, uuid) do
      runtime_info = body["agentRuntimeInfo"] || body
      _ = Agents.touch_agent_on_heartbeat(uuid, flatten_runtime_info(runtime_info))
      _ = Scheduler.try_assign_work(uuid)

      # NoWork representation matches GoCD's JSON format
      json(conn, %{"type" => "com.thoughtworks.go.remote.work.NoWork"})
    end
  end

  @doc """
  POST /remoting/api/agent/get_cookie

  Returns the stored cookie for the agent.
  """
  def get_cookie(conn, _params) do
    with {:ok, body} <- read_json_body(conn),
         uuid <- extract_uuid(body),
         :ok <- verify_agent_identity(conn, uuid) do
      case Agents.get_agent_by_uuid(uuid) do
        %{cookie: cookie} when is_binary(cookie) and cookie != "" ->
          text(conn, cookie)

        _ ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "No cookie available for agent"})
      end
    end
  end

  @doc """
  POST /remoting/api/agent/report_current_status

  Agent reports a job state change (e.g., Preparing, Building).
  """
  def report_current_status(conn, _params) do
    with {:ok, body} <- read_json_body(conn),
         uuid <- extract_uuid(body),
         :ok <- verify_agent_identity(conn, uuid) do
      AgentJobRuns.handle_agent_report(uuid, normalize_report_payload(body))
      send_resp(conn, 200, "")
    end
  end

  @doc """
  POST /remoting/api/agent/report_completing

  Agent reports a job is completing.
  """
  def report_completing(conn, _params) do
    with {:ok, body} <- read_json_body(conn),
         uuid <- extract_uuid(body),
         :ok <- verify_agent_identity(conn, uuid) do
      AgentJobRuns.handle_agent_report(uuid, normalize_report_payload(body))
      send_resp(conn, 200, "")
    end
  end

  @doc """
  POST /remoting/api/agent/report_completed

  Agent reports a job has completed.
  """
  def report_completed(conn, _params) do
    with {:ok, body} <- read_json_body(conn),
         uuid <- extract_uuid(body),
         :ok <- verify_agent_identity(conn, uuid) do
      AgentJobRuns.handle_agent_report(uuid, normalize_report_payload(body))
      send_resp(conn, 200, "")
    end
  end

  @doc """
  POST /remoting/api/agent/is_ignored

  Checks if a job is ignored. Currently always returns false.
  """
  def check_ignored(conn, _params) do
    with {:ok, body} <- read_json_body(conn),
         uuid <- extract_uuid(body),
         :ok <- verify_agent_identity(conn, uuid) do
      text(conn, "false")
    end
  end

  # --- Private helpers ---

  defp read_json_body(conn) do
    case conn.body_params do
      %{"_json" => body} when is_map(body) -> {:ok, body}
      body when is_map(body) and map_size(body) > 0 -> {:ok, body}
      _ -> {:ok, %{}}
    end
  end

  defp extract_uuid(body) do
    get_in(body, ["agentRuntimeInfo", "identifier", "uuid"]) ||
      get_in(body, ["identifier", "uuid"]) ||
      body["uuid"] ||
      "unknown"
  end

  defp verify_agent_identity(conn, uuid_from_body) do
    header_uuid = get_req_header(conn, "x-agent-guid") |> List.first()

    if is_nil(header_uuid) or header_uuid == uuid_from_body do
      :ok
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "Agent UUID mismatch: header '#{header_uuid}' vs body '#{uuid_from_body}'"
      })
      |> halt()
    end
  end

  # GoCD's AgentRuntimeInfo uses nested `identifier` with `uuid`, `hostName`, `ipAddress`.
  # Our `touch_agent_on_heartbeat` expects flat keys. This bridges the two formats.
  defp flatten_runtime_info(info) when is_map(info) do
    identifier = info["identifier"] || %{}

    %{}
    |> maybe_put("location", info["location"])
    |> maybe_put("usableSpace", info["usableSpace"])
    |> maybe_put("runtimeStatus", info["runtimeStatus"])
    |> maybe_put("operatingSystemName", info["operatingSystemName"])
    |> maybe_put("cookie", info["cookie"])
    |> maybe_put("hostname", identifier["hostName"])
    |> maybe_put("ipaddress", identifier["ipAddress"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp runtime_status(info) do
    info["runtimeStatus"]
  end

  # GoCD report payloads wrap job info under `jobIdentifier` and `jobState`/`result`.
  # Normalize to the flat format that `AgentJobRuns.handle_agent_report/2` expects.
  defp normalize_report_payload(body) do
    job_id = body["jobIdentifier"] || %{}
    build_id = to_string(job_id["buildId"] || body["buildId"] || "")

    %{
      "buildId" => build_id,
      "jobState" => body["jobState"],
      "result" => body["result"] || body["jobResult"],
      "agentRuntimeInfo" => body["agentRuntimeInfo"]
    }
  end
end
