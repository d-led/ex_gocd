defmodule ExGoCDWeb.API.AgentControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Repo
  alias ExGoCD.Agents
  alias ExGoCD.Agents.Agent

  @valid_uuid "550e8400-e29b-41d4-a716-446655440000"
  @another_uuid "650e8400-e29b-41d4-a716-446655440001"

  setup do
    # Clean up agents before each test
    Repo.delete_all(Agent)
    :ok
  end

  describe "POST /api/agents/register" do
    test "registers a new agent with valid data", %{conn: conn} do
      params = %{
        uuid: @valid_uuid,
        hostname: "build-agent-1",
        ipaddress: "192.168.1.100"
      }

      conn = post(conn, ~p"/api/agents/register", params)

      assert response = json_response(conn, 201)
      assert response["uuid"] == @valid_uuid
      assert response["hostname"] == "build-agent-1"
      assert response["ip_address"] == "192.168.1.100"
      assert response["agent_state"] == "Idle"
      assert response["agent_config_state"] == "Pending"
      assert response["build_state"] == "Idle"
      assert response["environments"] == []
      assert response["resources"] == []

      # Verify agent was created in database
      agent = Agents.get_agent_by_uuid(@valid_uuid)
      assert agent.hostname == "build-agent-1"
      assert agent.ipaddress == "192.168.1.100"
      assert agent.disabled == false
      assert agent.deleted == false
    end

    test "updates existing agent on re-registration", %{conn: conn} do
      # First registration
      {:ok, _agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "old-hostname",
          ipaddress: "192.168.1.100"
        })

      # Re-registration with updated hostname
      params = %{
        uuid: @valid_uuid,
        hostname: "new-hostname",
        ipaddress: "192.168.1.101"
      }

      conn = post(conn, ~p"/api/agents/register", params)

      assert response = json_response(conn, 201)
      assert response["uuid"] == @valid_uuid
      assert response["hostname"] == "new-hostname"
      assert response["ip_address"] == "192.168.1.101"

      # Verify only one agent exists
      assert Repo.aggregate(Agent, :count) == 1

      # Verify agent was updated
      agent = Agents.get_agent_by_uuid(@valid_uuid)
      assert agent.hostname == "new-hostname"
      assert agent.ipaddress == "192.168.1.101"
    end

    test "registers agent with environments and resources", %{conn: conn} do
      params = %{
        uuid: @valid_uuid,
        hostname: "build-agent-1",
        ipaddress: "192.168.1.100",
        environments: ["production", "testing"],
        resources: ["linux", "docker", "nodejs"]
      }

      conn = post(conn, ~p"/api/agents/register", params)

      assert %{
               "environments" => ["production", "testing"],
               "resources" => ["linux", "docker", "nodejs"]
             } = json_response(conn, 201)
    end

    test "rejects invalid UUID format", %{conn: conn} do
      params = %{
        uuid: "not-a-valid-uuid",
        hostname: "agent",
        ipaddress: "192.168.1.1"
      }

      conn = post(conn, ~p"/api/agents/register", params)

      assert %{"errors" => %{"uuid" => [_error]}} = json_response(conn, 422)
    end

    test "rejects invalid IP address", %{conn: conn} do
      params = %{
        uuid: @valid_uuid,
        hostname: "agent",
        ipaddress: "invalid-ip"
      }

      conn = post(conn, ~p"/api/agents/register", params)

      assert %{"errors" => %{"ipaddress" => [_error]}} = json_response(conn, 422)
    end

    test "validates elastic agent cannot have resources", %{conn: conn} do
      params = %{
        uuid: @valid_uuid,
        hostname: "elastic-agent",
        ipaddress: "192.168.1.100",
        elastic_agent_id: "elastic-1",
        elastic_plugin_id: "plugin-1",
        resources: ["linux"]
      }

      conn = post(conn, ~p"/api/agents/register", params)

      assert %{"errors" => %{"resources" => [error]}} = json_response(conn, 422)
      assert error =~ "Elastic agents cannot have resources"
    end
  end

  describe "GET /api/agents" do
    setup do
      # Create test agents
      {:ok, _} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent-1",
          ipaddress: "192.168.1.100"
        })

      {:ok, disabled_agent} =
        Agents.register_agent(%{
          uuid: @another_uuid,
          hostname: "agent-2",
          ipaddress: "192.168.1.101"
        })

      Agents.disable_agent(disabled_agent)

      :ok
    end

    test "lists all agents", %{conn: conn} do
      conn = get(conn, ~p"/api/agents")

      assert %{"_embedded" => %{"agents" => agents}} = json_response(conn, 200)
      assert length(agents) == 2
    end

    test "lists only active agents when active=true", %{conn: conn} do
      conn = get(conn, ~p"/api/agents?active=true")

      assert response = json_response(conn, 200)
      _agents = response["_embedded"]["agents"]
      assert length(response["_embedded"]["agents"]) == 1
      assert hd(response["_embedded"]["agents"])["uuid"] == @valid_uuid
    end
  end

  describe "GET /api/agents/:uuid" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent-1",
          ipaddress: "192.168.1.100",
          environments: ["production"],
          resources: ["linux", "docker"]
        })

      {:ok, agent: agent}
    end

    test "gets agent by UUID", %{conn: conn} do
      conn = get(conn, ~p"/api/agents/#{@valid_uuid}")

      assert response = json_response(conn, 200)
      assert response["uuid"] == @valid_uuid
      assert response["hostname"] == "agent-1"
      assert response["ip_address"] == "192.168.1.100"
      assert response["environments"] == ["production"]
      assert response["resources"] == ["linux", "docker"]
      assert response["_links"]["self"]["href"]
      assert response["_links"]["doc"]["href"]
    end

    test "returns 404 for non-existent agent", %{conn: conn} do
      conn = get(conn, ~p"/api/agents/#{@another_uuid}")

      assert %{"error" => "Agent not found"} = json_response(conn, 404)
    end
  end

  describe "PATCH /api/agents/:uuid" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent-1",
          ipaddress: "192.168.1.100",
          environments: ["dev"],
          resources: ["linux"]
        })

      {:ok, agent: agent}
    end

    test "updates agent environments", %{conn: conn} do
      conn =
        patch(conn, ~p"/api/agents/#{@valid_uuid}", %{environments: ["production", "staging"]})

      assert %{"environments" => ["production", "staging"]} = json_response(conn, 200)
    end

    test "updates agent resources", %{conn: conn} do
      conn =
        patch(conn, ~p"/api/agents/#{@valid_uuid}", %{resources: ["linux", "docker", "nodejs"]})

      assert %{"resources" => ["linux", "docker", "nodejs"]} = json_response(conn, 200)
    end

    test "updates agent disabled state", %{conn: conn} do
      conn = patch(conn, ~p"/api/agents/#{@valid_uuid}", %{disabled: true})

      assert %{"agent_state" => "Disabled"} = json_response(conn, 200)
    end

    test "returns 404 for non-existent agent", %{conn: conn} do
      conn = patch(conn, ~p"/api/agents/#{@another_uuid}", %{disabled: true})

      assert %{"error" => "Agent not found"} = json_response(conn, 404)
    end

    test "validates elastic agent cannot have resources", %{conn: conn, agent: agent} do
      # First, remove resources from the agent
      {:ok, updated_agent} = Agents.update_agent(agent, %{resources: []})

      # Then make it elastic
      {:ok, _elastic_agent} =
        Agents.update_agent(updated_agent, %{
          elastic_agent_id: "elastic-1",
          elastic_plugin_id: "plugin-1"
        })

      # Now try to add resources - this should fail
      conn = patch(conn, ~p"/api/agents/#{@valid_uuid}", %{resources: ["linux"]})

      assert %{"errors" => %{"resources" => [error]}} = json_response(conn, 422)
      assert error =~ "Elastic agents cannot have resources"
    end
  end

  describe "DELETE /api/agents/:uuid" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent-1",
          ipaddress: "192.168.1.100"
        })

      {:ok, agent: agent}
    end

    test "soft deletes an agent", %{conn: conn} do
      conn = delete(conn, ~p"/api/agents/#{@valid_uuid}")

      assert response(conn, 204)

      # Verify agent is marked as deleted but still in database
      agent = Agents.get_agent_by_uuid(@valid_uuid)
      assert agent.deleted == true

      # Verify it doesn't show up in active agents
      assert Agents.list_active_agents() == []
    end

    test "returns 404 for non-existent agent", %{conn: conn} do
      conn = delete(conn, ~p"/api/agents/#{@another_uuid}")

      assert %{"error" => "Agent not found"} = json_response(conn, 404)
    end
  end

  describe "PUT /api/agents/:uuid/enable" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent-1",
          ipaddress: "192.168.1.100"
        })

      Agents.disable_agent(agent)

      {:ok, agent: agent}
    end

    test "enables a disabled agent", %{conn: conn} do
      conn = put(conn, ~p"/api/agents/#{@valid_uuid}/enable")

      assert %{"agent_state" => agent_state} = json_response(conn, 200)
      assert agent_state in ["Idle", "Building"]

      # Verify agent is enabled in database
      agent = Agents.get_agent_by_uuid(@valid_uuid)
      assert agent.disabled == false
    end

    test "returns 404 for non-existent agent", %{conn: conn} do
      conn = put(conn, ~p"/api/agents/#{@another_uuid}/enable")

      assert %{"error" => "Agent not found"} = json_response(conn, 404)
    end
  end

  describe "PUT /api/agents/:uuid/disable" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent-1",
          ipaddress: "192.168.1.100"
        })

      {:ok, agent: agent}
    end

    test "disables an enabled agent", %{conn: conn} do
      conn = put(conn, ~p"/api/agents/#{@valid_uuid}/disable")

      assert %{"agent_state" => "Disabled"} = json_response(conn, 200)

      # Verify agent is disabled in database
      agent = Agents.get_agent_by_uuid(@valid_uuid)
      assert agent.disabled == true
    end

    test "returns 404 for non-existent agent", %{conn: conn} do
      conn = put(conn, ~p"/api/agents/#{@another_uuid}/disable")

      assert %{"error" => "Agent not found"} = json_response(conn, 404)
    end
  end
end
