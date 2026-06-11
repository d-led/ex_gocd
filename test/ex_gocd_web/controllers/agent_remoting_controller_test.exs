defmodule ExGoCDWeb.AgentRemotingControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Repo
  alias ExGoCD.Agents
  alias ExGoCD.Agents.Agent

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

  defp ping_payload(uuid \\ @agent_uuid, cookie \\ nil) do
    %{
      "agentRuntimeInfo" => %{
        "identifier" => %{
          "uuid" => uuid,
          "hostName" => "build-agent-1",
          "ipAddress" => "192.168.1.100"
        },
        "runtimeStatus" => "Idle",
        "location" => "/var/lib/go-agent",
        "usableSpace" => 10_000_000_000,
        "operatingSystemName" => "Linux",
        "cookie" => cookie
      }
    }
  end

  defp report_payload(uuid \\ @agent_uuid) do
    %{
      "agentRuntimeInfo" => %{
        "identifier" => %{"uuid" => uuid},
        "runtimeStatus" => "Building"
      },
      "jobIdentifier" => %{
        "buildId" => "42",
        "pipelineName" => "test-pipeline",
        "stageName" => "test-stage",
        "jobName" => "test-job"
      },
      "jobState" => "Building"
    }
  end

  describe "POST /remoting/api/agent/ping" do
    test "updates agent runtime info and returns NONE instruction", %{conn: conn, agent: agent} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/ping", ping_payload(@agent_uuid, agent.cookie))

      assert %{"agentInstruction" => "NONE"} = json_response(conn, 200)

      agent = Agents.get_agent_by_uuid(@agent_uuid)
      assert agent.state == "Idle"
      assert agent.operating_system == "Linux"
    end

    test "works via /go/remoting/api/agent/ping path too", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/go/remoting/api/agent/ping", ping_payload())

      assert %{"agentInstruction" => "NONE"} = json_response(conn, 200)
    end

    test "accepts ping without X-Agent-GUID header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/ping", ping_payload())

      assert %{"agentInstruction" => "NONE"} = json_response(conn, 200)
    end

    test "rejects ping when X-Agent-GUID mismatches body UUID", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-agent-guid", "wrong-uuid")
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/ping", ping_payload())

      assert json_response(conn, 403)["error"] =~ "UUID mismatch"
    end
  end

  describe "POST /remoting/api/agent/get_work" do
    test "returns NoWork when no jobs are queued", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/get_work", ping_payload())

      response = json_response(conn, 200)
      assert response["type"] == "com.thoughtworks.go.remote.work.NoWork"
    end
  end

  describe "POST /remoting/api/agent/get_cookie" do
    test "returns the stored cookie for an enabled agent", %{conn: conn, agent: agent} do
      assert agent.cookie != nil

      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/get_cookie", ping_payload())

      assert response(conn, 200) == agent.cookie
    end
  end

  describe "POST /remoting/api/agent/report_current_status" do
    test "accepts report and returns 200", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/report_current_status", report_payload())

      assert response(conn, 200)
    end
  end

  describe "POST /remoting/api/agent/report_completing" do
    test "accepts report and returns 200", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/report_completing", report_payload())

      assert response(conn, 200)
    end
  end

  describe "POST /remoting/api/agent/report_completed" do
    test "accepts report and returns 200", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/report_completed", report_payload())

      assert response(conn, 200)
    end
  end

  describe "POST /remoting/api/agent/is_ignored" do
    test "returns false", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-agent-guid", @agent_uuid)
        |> put_req_header("content-type", "application/json")
        |> post("/remoting/api/agent/is_ignored", ping_payload())

      assert response(conn, 200) == "false"
    end
  end
end
