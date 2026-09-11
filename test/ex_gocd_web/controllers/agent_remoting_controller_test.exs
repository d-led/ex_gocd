defmodule ExGoCDWeb.AgentRemotingControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents
  alias ExGoCD.Agents.Agent
  alias ExGoCD.RemotingFixture
  alias ExGoCD.Repo

  @agent_uuid "550e8400-e29b-41d4-a716-446655440000"

  setup do
    Repo.delete_all(Agent)

    {:ok, agent} =
      Agents.register_agent(%{
        uuid: @agent_uuid,
        hostname: "build-agent-1",
        ipaddress: "192.168.1.100"
      })

    {:ok, _} = Agents.enable_agent(agent)
    %{agent: Agents.get_agent_by_uuid(@agent_uuid)}
  end

  # The captured traffic is the specification: send exactly what the official
  # Java agent sends, and require exactly what the official server answers.
  # Only the agent's own credentials are substituted, because an agent proves
  # its identity with the UUID and the cookie it was issued at registration.
  defp captured(name, agent) do
    name
    |> RemotingFixture.json()
    |> with_agent_credentials(agent)
  end

  defp with_agent_credentials(%{"agentRuntimeInfo" => _} = body, agent) do
    body
    |> put_in(["agentRuntimeInfo", "identifier", "uuid"], agent.uuid)
    |> put_in(["agentRuntimeInfo", "cookie"], agent.cookie)
  end

  defp with_agent_credentials(body, agent) do
    Map.put(body, "agentRuntimeInfo", %{
      "type" => "AgentRuntimeInfo",
      "identifier" => %{
        "uuid" => agent.uuid,
        "hostName" => "build-agent-1",
        "ipAddress" => "192.168.1.100"
      },
      "runtimeStatus" => "Building",
      "cookie" => agent.cookie
    })
  end

  defp post_remoting(conn, action, body) do
    conn
    |> put_req_header("x-agent-guid", @agent_uuid)
    |> put_req_header("accept", "application/vnd.go.cd+json")
    |> put_req_header("content-type", "application/json; charset=UTF-8")
    |> post("/remoting/api/agent/#{action}", body)
  end

  describe "POST /remoting/api/agent/ping" do
    test "answers with the NONE instruction exactly as GoCD does", %{conn: conn, agent: agent} do
      conn = post_remoting(conn, "ping", captured("ping_request.json", agent))

      assert response(conn, 200) == RemotingFixture.raw("ping_response.json")
    end

    test "records the agent's runtime information", %{conn: conn, agent: agent} do
      post_remoting(conn, "ping", captured("ping_request.json", agent))

      agent = Agents.get_agent_by_uuid(@agent_uuid)
      assert agent.state == "Idle"
      assert agent.operating_system =~ "Alpine"
    end

    test "is served on the /go prefixed path too, because servers usually sit behind /go",
         %{conn: conn, agent: agent} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/go/remoting/api/agent/ping", captured("ping_request.json", agent))

      assert response(conn, 200) == RemotingFixture.raw("ping_response.json")
    end

    test "refuses a request that claims another agent's identity", %{conn: conn, agent: agent} do
      conn =
        conn
        |> put_req_header("x-agent-guid", "a-different-agent")
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/ping", captured("ping_request.json", agent))

      assert json_response(conn, 403)["error"] =~ "UUID mismatch"
    end
  end

  describe "POST /remoting/api/agent/get_work" do
    test "answers NoWork in GoCD's format when the agent has nothing to do",
         %{conn: conn, agent: agent} do
      conn = post_remoting(conn, "get_work", captured("get_work_request.json", agent))

      assert json_response(conn, 200) == RemotingFixture.json("no_work_response.json")
    end

    test "hands out a queued build as BuildWork", %{conn: conn, agent: agent} do
      assign_work_to_agent()

      conn = post_remoting(conn, "get_work", captured("get_work_request.json", agent))
      body = json_response(conn, 200)

      assert body["type"] == "BuildWork"
      assert body["consoleLogCharset"] == "UTF-8"

      assert %{"pipelineName" => "demo", "buildName" => "unit-tests"} =
               body["assignment"]["jobIdentifier"]

      assert [%{"type" => "CommandBuilderWithArgList", "command" => "echo"}] =
               body["assignment"]["builders"]
    end

    test "hands the same build to only one caller", %{conn: conn, agent: agent} do
      assign_work_to_agent()

      first = post_remoting(conn, "get_work", captured("get_work_request.json", agent))
      second = post_remoting(conn, "get_work", captured("get_work_request.json", agent))

      assert json_response(first, 200)["type"] == "BuildWork"
      assert json_response(second, 200) == %{"type" => "NoWork"}
    end
  end

  describe "POST /remoting/api/agent/get_cookie" do
    test "returns the cookie as bare text, as the agent's JSON parser expects",
         %{conn: conn, agent: agent} do
      conn = post_remoting(conn, "get_cookie", captured("get_cookie_request.json", agent))

      assert response(conn, 200) == agent.cookie
    end
  end

  describe "POST /remoting/api/agent/report_current_status" do
    test "moves the job run into the reported state", %{conn: conn, agent: agent} do
      run = assign_work_to_agent_and_claim()

      conn =
        post_remoting(
          conn,
          "report_current_status",
          report_payload(run, agent, "jobState", "Building")
        )

      assert response(conn, 200) == ""
      assert AgentJobRuns.get_run_by_id(run.id).state == "Building"
    end
  end

  describe "POST /remoting/api/agent/report_completing" do
    test "records the result the agent reports", %{conn: conn, agent: agent} do
      run = assign_work_to_agent_and_claim()

      conn =
        post_remoting(
          conn,
          "report_completing",
          report_payload(run, agent, "jobResult", "Passed")
        )

      assert response(conn, 200) == ""

      updated = AgentJobRuns.get_run_by_id(run.id)
      assert updated.state == "Completing"
      assert updated.result == "Passed"
    end
  end

  describe "POST /remoting/api/agent/report_completed" do
    test "marks the job run completed with its result", %{conn: conn, agent: agent} do
      run = assign_work_to_agent_and_claim()

      conn =
        post_remoting(conn, "report_completed", report_payload(run, agent, "jobResult", "Passed"))

      assert response(conn, 200) == ""

      updated = AgentJobRuns.get_run_by_id(run.id)
      assert updated.state == "Completed"
      assert updated.result == "Passed"
    end
  end

  describe "POST /remoting/api/agent/is_ignored" do
    test "tells the agent to carry on when the job is still wanted", %{conn: conn, agent: agent} do
      run = assign_work_to_agent_and_claim()

      conn = post_remoting(conn, "is_ignored", is_ignored_payload(run, agent))

      assert response(conn, 200) == RemotingFixture.raw("is_ignored_response.txt")
    end

    test "tells the agent to stop when its job has been cancelled", %{conn: conn, agent: agent} do
      run = assign_work_to_agent_and_claim()
      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, run.build_id, "Cancelled")

      conn = post_remoting(conn, "is_ignored", is_ignored_payload(run, agent))

      assert response(conn, 200) == "true"
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp assign_work_to_agent do
    {:ok, run} =
      AgentJobRuns.create_run(@agent_uuid, "build-42", "demo", "test", "unit-tests")

    {:ok, run} =
      AgentJobRuns.store_work_payload(run.build_id, %{
        "buildCommand" => %{
          "name" => "compose",
          "subCommands" => [
            %{
              "name" => "exec",
              "command" => "echo",
              "args" => ["hello"],
              "workingDirectory" => ""
            }
          ]
        }
      })

    run
  end

  defp assign_work_to_agent_and_claim do
    run = assign_work_to_agent()
    {:ok, claimed} = AgentJobRuns.claim_work_for_agent(@agent_uuid)
    assert claimed.id == run.id
    run
  end

  defp report_payload(run, agent, field, value) do
    "report_current_status_request.json"
    |> captured(agent)
    |> Map.drop(["jobState", "jobResult"])
    |> Map.put("jobIdentifier", job_identifier(run))
    |> Map.put(field, value)
  end

  defp is_ignored_payload(run, agent) do
    "is_ignored_request.json"
    |> captured(agent)
    |> Map.put("jobIdentifier", job_identifier(run))
  end

  defp job_identifier(run) do
    %{
      "pipelineName" => run.pipeline_name,
      "pipelineCounter" => run.pipeline_counter,
      "pipelineLabel" => to_string(run.pipeline_counter),
      "stageName" => run.stage_name,
      "stageCounter" => to_string(run.stage_counter),
      "buildName" => run.job_name,
      "buildId" => run.id
    }
  end
end
