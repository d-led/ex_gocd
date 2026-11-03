defmodule ExGoCD.HTTPTestAgentTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Agents
  alias ExGoCD.Agents.Agent
  alias ExGoCD.Repo

  @agent_uuid "550e8400-e29b-41d4-a716-446655500008"

  setup do
    Repo.delete_all(Agent)
    :ok
  end

  describe "POST /admin/agent (legacy agent registration)" do
    test "registers agent with form data matching HTTPTestAgent format", %{conn: conn} do
      params = %{
        "uuid" => @agent_uuid,
        "hostname" => "http-test-agent-550e8400",
        "ipAddress" => "127.0.0.1",
        "location" => "./work-http",
        "usablespace" => "10737418240",
        "operatingSystem" => "Simulated HTTP"
      }

      conn = post(conn, "/admin/agent", params)

      assert response(conn, 200)

      agent = Agents.get_agent_by_uuid(@agent_uuid)
      assert agent != nil
      assert agent.hostname == "http-test-agent-550e8400"
      assert agent.ipaddress == "127.0.0.1"
      assert agent.state == "Idle"
    end

    test "registers agent with resources and environments", %{conn: conn} do
      params = %{
        "uuid" => @agent_uuid,
        "hostname" => "agent-with-resources",
        "ipAddress" => "127.0.0.1",
        "location" => "./work",
        "operatingSystem" => "Linux",
        "agentAutoRegisterResources" => "linux,docker",
        "agentAutoRegisterEnvironments" => "staging,production"
      }

      conn = post(conn, "/admin/agent", params)

      assert response(conn, 200)

      agent = Agents.get_agent_by_uuid(@agent_uuid)
      assert agent.resources == ["linux", "docker"]
      assert agent.environments == ["staging", "production"]
    end

    test "returns bad request when uuid is missing", %{conn: conn} do
      params = %{
        "hostname" => "no-uuid-agent",
        "ipAddress" => "127.0.0.1"
      }

      conn = post(conn, "/admin/agent", params)

      assert json_response(conn, 400)["error"] =~ "Missing required fields"
    end

    test "returns bad request when hostname is missing", %{conn: conn} do
      params = %{
        "uuid" => @agent_uuid,
        "ipAddress" => "127.0.0.1"
      }

      conn = post(conn, "/admin/agent", params)

      assert json_response(conn, 400)["error"] =~ "Missing required fields"
    end
  end

  describe "GET /admin/agent/token" do
    test "answers the same token every time, so an agent that lost its copy can ask again", %{
      conn: conn
    } do
      first = conn |> get("/admin/agent/token?uuid=#{@agent_uuid}") |> response(200)
      second = conn |> get("/admin/agent/token?uuid=#{@agent_uuid}") |> response(200)

      assert first == second
      assert first == ExGoCD.Agents.Token.for_agent(@agent_uuid)
    end

    test "answers a different token for a different agent", %{conn: conn} do
      other = conn |> get("/admin/agent/token?uuid=another-agent") |> response(200)

      assert other != ExGoCD.Agents.Token.for_agent(@agent_uuid)
    end
  end
end
