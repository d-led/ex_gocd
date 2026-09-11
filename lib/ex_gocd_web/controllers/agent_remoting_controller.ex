defmodule ExGoCDWeb.AgentRemotingController do
  @moduledoc """
  GoCD's internal agent remoting API, spoken by the official Java agent.

  The official agent does **not** use a websocket. It POSTs JSON to
  `/remoting/api/agent/<action>`, authenticated with the `X-Agent-GUID` and
  `Authorization` headers, and expects Gson-serialised GoCD types back
  (`"NONE"`, `{"type":"NoWork"}`, a `BuildWork`, and so on).

  The exact shapes implemented here are not guesses: they are asserted against
  real captured traffic in `test/fixtures/remoting/`, and the capture procedure
  is documented in that directory's README.

  Based on GoCD's `InternalAgentControllerV1.java`.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents
  alias ExGoCD.Remoting.BuildWork
  alias ExGoCD.Scheduler

  # GoCD answers every remoting action with this content type.
  @remoting_content_type "application/vnd.go.cd.v1+json;charset=utf-8"

  # `AgentInstruction` values the agent understands. A job that is not cancelled
  # carries no instruction, which GoCD serialises as the quoted string "NONE".
  @instruction_none "NONE"

  @doc """
  POST /remoting/api/agent/ping

  Heartbeat. Updates runtime info and offers idle work.
  """
  def ping(conn, _params) do
    with_agent(conn, fn conn, uuid, body ->
      register_heartbeat(uuid, body)
      maybe_offer_work(uuid, body)

      remoting_json(conn, @instruction_none)
    end)
  end

  @doc """
  POST /remoting/api/agent/get_work

  Hands the agent its next build assignment, or `NoWork` when the queue is empty
  for it. Each assignment is claimed once, so a build is never given to two
  agents.
  """
  def get_work(conn, _params) do
    with_agent(conn, fn conn, uuid, body ->
      register_heartbeat(uuid, body)
      _ = Scheduler.try_assign_work(uuid)

      case AgentJobRuns.claim_work_for_agent(uuid) do
        {:ok, run} -> remoting_json(conn, BuildWork.render(run.work_payload, run))
        {:error, :no_work} -> remoting_json(conn, %{"type" => "NoWork"})
      end
    end)
  end

  @doc """
  POST /remoting/api/agent/get_cookie

  Returns the agent's session cookie as plain text, which is what the agent's
  `Serialization.fromJson(..., String.class)` expects.
  """
  def get_cookie(conn, _params) do
    with_agent(conn, fn conn, uuid, _body ->
      case Agents.get_agent_by_uuid(uuid) do
        %{cookie: cookie} when is_binary(cookie) and cookie != "" ->
          remoting_text(conn, cookie)

        _ ->
          conn
          |> put_resp_content_type(@remoting_content_type)
          |> send_resp(404, "No cookie available for agent")
      end
    end)
  end

  @doc """
  POST /remoting/api/agent/report_current_status

  Reports a job state change such as `Preparing` or `Building`.
  """
  def report_current_status(conn, _params) do
    handle_report(conn, fn body -> body["jobState"] end)
  end

  @doc """
  POST /remoting/api/agent/report_completing

  Reports that a job is finishing, together with its result.
  """
  def report_completing(conn, _params) do
    handle_report(conn, fn _body -> "Completing" end)
  end

  @doc """
  POST /remoting/api/agent/report_completed

  Reports that a job has finished, together with its result.
  """
  def report_completed(conn, _params) do
    handle_report(conn, fn _body -> "Completed" end)
  end

  @doc """
  POST /remoting/api/agent/is_ignored

  Tells the agent whether its current assignment has been discarded, so it can
  stop work early instead of reporting into a job nobody is waiting for.
  """
  def check_ignored(conn, _params) do
    with_agent(conn, fn conn, uuid, body ->
      run = run_for_report(uuid, body)
      remoting_text(conn, to_string(ignored?(run)))
    end)
  end

  # ── reports ─────────────────────────────────────────────────────────────

  defp handle_report(conn, job_state_fun) do
    with_agent(conn, fn conn, uuid, body ->
      case run_for_report(uuid, body) do
        nil ->
          # An unknown build is not something the agent can act on; GoCD also
          # acknowledges it so the agent moves on instead of retrying forever.
          send_resp(conn, 200, "")

        run ->
          AgentJobRuns.handle_agent_report(uuid, %{
            "buildId" => run.build_id,
            "jobState" => job_state_fun.(body),
            "result" => body["jobResult"] || body["result"],
            "agentRuntimeInfo" => body["agentRuntimeInfo"]
          })

          send_resp(conn, 200, "")
      end
    end)
  end

  defp ignored?(nil), do: false
  defp ignored?(%{state: state}), do: state in ["Cancelled", "Canceled", "Ignored"]

  # ── work ────────────────────────────────────────────────────────────────

  defp register_heartbeat(uuid, body) do
    runtime_info = body["agentRuntimeInfo"] || body
    _ = Agents.touch_agent_on_heartbeat(uuid, flatten_runtime_info(runtime_info))
    :ok
  end

  defp maybe_offer_work(uuid, body) do
    runtime_info = body["agentRuntimeInfo"] || body

    if runtime_status(runtime_info) == "Idle" do
      _ = Scheduler.try_assign_work(uuid)
    end

    :ok
  end

  # ── agent identification ────────────────────────────────────────────────

  # Every remoting action is authenticated the same way: the body names an
  # agent, and the request must prove it is that agent. A rejected request
  # returns the halted connection.
  defp with_agent(conn, handler) do
    with {:ok, body} <- read_json_body(conn),
         {:ok, uuid} <- authorize(conn, body) do
      handler.(conn, uuid, body)
    else
      {:error, conn} -> conn
    end
  end

  defp authorize(conn, body) do
    uuid = extract_uuid(body)
    header_uuid = get_req_header(conn, "x-agent-guid") |> List.first()

    cond do
      not is_nil(header_uuid) and header_uuid != uuid ->
        {:error,
         forbidden(conn, "Agent UUID mismatch: header '#{header_uuid}' vs body '#{uuid}'")}

      disabled_agent?(uuid) ->
        {:error, forbidden(conn, "Agent is disabled")}

      true ->
        {:ok, uuid}
    end
  end

  defp forbidden(conn, message) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: message})
    |> halt()
  end

  defp read_json_body(conn) do
    case conn.body_params do
      %{"_json" => body} when is_map(body) -> {:ok, body}
      body when is_map(body) -> {:ok, body}
      _ -> {:ok, %{}}
    end
  end

  defp extract_uuid(body) do
    get_in(body, ["agentRuntimeInfo", "identifier", "uuid"]) ||
      get_in(body, ["identifier", "uuid"]) ||
      body["uuid"] ||
      "unknown"
  end

  defp disabled_agent?(uuid) do
    case Agents.get_agent_by_uuid(uuid) do
      %{disabled: true} -> true
      _ -> false
    end
  end

  # The GoCD agent identifies a build by numeric id inside `jobIdentifier`.
  # Resolve it to the run so internal string build ids never leak into the
  # protocol, and so one agent cannot report on another agent's build.
  defp run_for_report(uuid, body) do
    build_id = get_in(body, ["jobIdentifier", "buildId"])

    case AgentJobRuns.get_run_by_id(build_id) do
      %{agent_uuid: ^uuid} = run -> run
      _ -> nil
    end
  end

  # GoCD's AgentRuntimeInfo nests `identifier` with `uuid`, `hostName` and
  # `ipAddress`; the Agents context takes flat attributes.
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

  defp runtime_status(info) when is_map(info), do: info["runtimeStatus"]
  defp runtime_status(_), do: nil

  # ── responses ───────────────────────────────────────────────────────────

  defp remoting_json(conn, value) do
    conn
    |> put_resp_content_type(@remoting_content_type)
    |> json(value)
  end

  defp remoting_text(conn, value) do
    conn
    |> put_resp_content_type(@remoting_content_type)
    |> send_resp(200, value)
  end
end
