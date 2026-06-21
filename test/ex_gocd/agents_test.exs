defmodule ExGoCD.AgentsTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Agents
  alias ExGoCD.Agents.Agent

  @valid_uuid "550e8400-e29b-41d4-a716-446655440000"
  @another_uuid "650e8400-e29b-41d4-a716-446655440001"

  describe "register_agent/1" do
    test "creates new agent with valid attributes" do
      attrs = %{
        uuid: @valid_uuid,
        hostname: "build-agent-1",
        ipaddress: "192.168.1.100"
      }

      assert {:ok, %Agent{} = agent} = Agents.register_agent(attrs)
      assert agent.uuid == @valid_uuid
      assert agent.hostname == "build-agent-1"
      assert agent.ipaddress == "192.168.1.100"
      assert agent.disabled == false
      assert agent.deleted == false
      assert agent.environments == []
      assert agent.resources == []
    end

    test "creates agent with environments and resources" do
      attrs = %{
        uuid: @valid_uuid,
        hostname: "agent-1",
        ipaddress: "192.168.1.100",
        environments: ["production", "staging"],
        resources: ["linux", "docker"]
      }

      assert {:ok, agent} = Agents.register_agent(attrs)
      assert agent.environments == ["production", "staging"]
      assert agent.resources == ["linux", "docker"]
    end

    test "updates existing agent on re-registration" do
      # Initial registration
      {:ok, _} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "old-hostname",
          ipaddress: "192.168.1.100"
        })

      # Re-registration with new hostname
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "new-hostname",
          ipaddress: "192.168.1.101"
        })

      assert agent.hostname == "new-hostname"
      assert agent.ipaddress == "192.168.1.101"

      # Only one agent should exist
      assert Repo.aggregate(Agent, :count) == 1
    end

    test "requires uuid" do
      attrs = %{hostname: "agent", ipaddress: "192.168.1.1"}
      assert {:error, changeset} = Agents.register_agent(attrs)
      assert "can't be blank" in errors_on(changeset).uuid
    end

    test "requires hostname" do
      attrs = %{uuid: @valid_uuid, ipaddress: "192.168.1.1"}
      assert {:error, changeset} = Agents.register_agent(attrs)
      assert "can't be blank" in errors_on(changeset).hostname
    end

    test "requires ipaddress" do
      attrs = %{uuid: @valid_uuid, hostname: "agent"}
      assert {:error, changeset} = Agents.register_agent(attrs)
      assert "can't be blank" in errors_on(changeset).ipaddress
    end

    test "validates UUID format" do
      attrs = %{uuid: "not-a-uuid", hostname: "agent", ipaddress: "192.168.1.1"}
      assert {:error, changeset} = Agents.register_agent(attrs)
      assert "must be a valid UUID" in errors_on(changeset).uuid
    end

    test "validates IP address format" do
      attrs = %{uuid: @valid_uuid, hostname: "agent", ipaddress: "invalid-ip"}
      assert {:error, changeset} = Agents.register_agent(attrs)
      assert "is not a valid IP address" in errors_on(changeset).ipaddress
    end

    test "accepts IPv4 address" do
      attrs = %{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.100"}
      assert {:ok, agent} = Agents.register_agent(attrs)
      assert agent.ipaddress == "192.168.1.100"
    end

    test "accepts IPv6 address" do
      attrs = %{uuid: @valid_uuid, hostname: "agent", ipaddress: "2001:db8::8a2e:370:7334"}
      assert {:ok, agent} = Agents.register_agent(attrs)
      assert agent.ipaddress == "2001:db8::8a2e:370:7334"
    end

    test "prevents elastic agent from having resources" do
      attrs = %{
        uuid: @valid_uuid,
        hostname: "elastic-agent",
        ipaddress: "192.168.1.100",
        elastic_agent_id: "elastic-1",
        elastic_plugin_id: "plugin-1",
        resources: ["linux"]
      }

      assert {:error, changeset} = Agents.register_agent(attrs)
      assert "Elastic agents cannot have resources" in errors_on(changeset).resources
    end

    test "allows elastic agent without resources" do
      attrs = %{
        uuid: @valid_uuid,
        hostname: "elastic-agent",
        ipaddress: "192.168.1.100",
        elastic_agent_id: "elastic-1",
        elastic_plugin_id: "plugin-1",
        resources: []
      }

      assert {:ok, agent} = Agents.register_agent(attrs)
      assert agent.elastic_agent_id == "elastic-1"
      assert agent.resources == []
    end
  end

  describe "list_agents/0" do
    test "returns all agents including disabled and deleted" do
      {:ok, _agent1} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "a1", ipaddress: "192.168.1.1"})

      {:ok, agent2} =
        Agents.register_agent(%{uuid: @another_uuid, hostname: "a2", ipaddress: "192.168.1.2"})

      Agents.disable_agent(agent2)

      agents = Agents.list_agents()
      assert length(agents) == 2
    end

    test "returns empty list when no agents exist" do
      assert Agents.list_agents() == []
    end
  end

  describe "list_active_agents/0" do
    setup do
      {:ok, enabled} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "enabled", ipaddress: "192.168.1.1"})

      {:ok, disabled} =
        Agents.register_agent(%{
          uuid: "550e8400-e29b-41d4-a716-446655440002",
          hostname: "disabled",
          ipaddress: "192.168.1.2"
        })

      {:ok, deleted} =
        Agents.register_agent(%{
          uuid: "550e8400-e29b-41d4-a716-446655440003",
          hostname: "deleted",
          ipaddress: "192.168.1.3"
        })

      Agents.disable_agent(disabled)
      Agents.disable_agent(deleted)
      Agents.delete_agent(deleted)

      %{enabled: enabled}
    end

    test "returns only enabled and not deleted agents", %{enabled: enabled} do
      agents = Agents.list_active_agents()
      assert length(agents) == 1
      assert hd(agents).id == enabled.id
    end

    test "excludes disabled agents" do
      agents = Agents.list_active_agents()
      refute Enum.any?(agents, &(&1.disabled == true))
    end

    test "excludes deleted agents" do
      agents = Agents.list_active_agents()
      refute Enum.any?(agents, &(&1.deleted == true))
    end
  end

  describe "get_agent_by_uuid/1" do
    test "returns agent when found" do
      {:ok, _} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      agent = Agents.get_agent_by_uuid(@valid_uuid)
      assert agent.uuid == @valid_uuid
    end

    test "returns nil when not found" do
      assert Agents.get_agent_by_uuid(@valid_uuid) == nil
    end
  end

  describe "update_agent/2" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      %{agent: agent}
    end

    test "updates agent attributes", %{agent: agent} do
      {:ok, updated} = Agents.update_agent(agent, %{hostname: "new-hostname"})
      assert updated.hostname == "new-hostname"
    end

    test "updates environments", %{agent: agent} do
      {:ok, updated} = Agents.update_agent(agent, %{environments: ["prod", "staging"]})
      assert updated.environments == ["prod", "staging"]
    end

    test "validates elastic agent resources rule", %{agent: agent} do
      # Make it elastic
      {:ok, elastic_agent} =
        Agents.update_agent(agent, %{
          elastic_agent_id: "elastic-1",
          elastic_plugin_id: "plugin-1"
        })

      # Should fail when trying to add resources
      {:error, changeset} = Agents.update_agent(elastic_agent, %{resources: ["linux"]})
      assert "Elastic agents cannot have resources" in errors_on(changeset).resources
    end
  end

  describe "mark_lost_contact/1" do
    test "sets state to LostContact when agent is enabled (e.g. WebSocket disconnected)" do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      assert :ok = Agents.mark_lost_contact(agent.uuid)
      updated = Agents.get_agent_by_uuid(agent.uuid)
      assert updated.state == "LostContact"
      assert Agents.effective_status(updated) == :lost_contact
    end

    test "does not update state when agent is disabled" do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      {:ok, disabled} = Agents.disable_agent(agent)
      assert :ok = Agents.mark_lost_contact(disabled.uuid)
      updated = Agents.get_agent_by_uuid(disabled.uuid)
      assert updated.state == disabled.state
      assert updated.disabled == true
    end

    test "returns {:error, :not_found} when agent uuid does not exist" do
      assert {:error, :not_found} =
               Agents.mark_lost_contact("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "update_agent_runtime_state/2" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      %{agent: agent}
    end

    test "updates agent state so UI shows Building/Idle without waiting for ping", %{agent: agent} do
      assert :ok = Agents.update_agent_runtime_state(agent.uuid, "Building")
      assert %{state: "Building"} = Agents.get_agent_by_uuid(agent.uuid) |> Map.take([:state])

      assert :ok = Agents.update_agent_runtime_state(agent.uuid, "Idle")
      assert %{state: "Idle"} = Agents.get_agent_by_uuid(agent.uuid) |> Map.take([:state])
    end

    test "returns :error when agent not found" do
      assert {:error, :not_found} =
               Agents.update_agent_runtime_state("00000000-0000-0000-0000-000000000000", "Idle")
    end
  end

  describe "enable_agent/1 and disable_agent/1" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      %{agent: agent}
    end

    test "enables an agent", %{agent: agent} do
      {:ok, disabled} = Agents.disable_agent(agent)
      assert disabled.disabled == true

      {:ok, enabled} = Agents.enable_agent(disabled)
      assert enabled.disabled == false
    end

    test "disables an agent", %{agent: agent} do
      {:ok, disabled} = Agents.disable_agent(agent)
      assert disabled.disabled == true
    end
  end

  describe "delete_agent/1" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      %{agent: agent}
    end

    test "soft deletes an agent when disabled", %{agent: agent} do
      {:ok, disabled} = Agents.disable_agent(agent)
      {:ok, deleted} = Agents.delete_agent(disabled)
      assert deleted.deleted == true

      assert Agents.get_agent_by_uuid(@valid_uuid) != nil
    end

    test "returns error when agent not disabled", %{agent: agent} do
      assert {:error, :agent_not_disabled} = Agents.delete_agent(agent)
    end

    test "deleted agent not in active list", %{agent: agent} do
      {:ok, disabled} = Agents.disable_agent(agent)
      {:ok, _deleted} = Agents.delete_agent(disabled)

      assert Agents.list_active_agents() == []
    end
  end

  describe "touch_agent_on_heartbeat/2" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent",
          ipaddress: "192.168.1.1",
          cookie: "agent-token-123"
        })

      %{agent: agent}
    end

    test "updates agent and refreshes updated_at when cookie matches", %{agent: agent} do
      runtime = %{
        "cookie" => "agent-token-123",
        "location" => "/work",
        "runtimeStatus" => "Idle",
        "operatingSystemName" => "darwin",
        "usableSpace" => 10_000_000_000
      }

      assert :ok = Agents.touch_agent_on_heartbeat(agent.uuid, runtime)

      updated = Agents.get_agent_by_uuid(agent.uuid)
      assert updated.working_dir == "/work"
      assert updated.state == "Idle"
      assert updated.operating_system == "darwin"
      assert updated.free_space == 10_000_000_000
      assert NaiveDateTime.compare(updated.updated_at, agent.updated_at) in [:gt, :eq]
    end

    test "returns :error when cookie does not match", %{agent: agent} do
      runtime = %{"cookie" => "wrong-token", "location" => "/work"}

      assert {:error, :cookie_mismatch} = Agents.touch_agent_on_heartbeat(agent.uuid, runtime)

      updated = Agents.get_agent_by_uuid(agent.uuid)
      assert updated.working_dir != "/work"
    end

    test "accepts Cookie (capital C) from payload", %{agent: agent} do
      runtime = %{"Cookie" => "agent-token-123", "runtimeStatus" => "Idle"}

      assert :ok = Agents.touch_agent_on_heartbeat(agent.uuid, runtime)
    end

    test "refreshes updated_at even when no other attrs change so status stays Idle", %{agent: agent} do
      runtime = %{"cookie" => "agent-token-123"}

      assert :ok = Agents.touch_agent_on_heartbeat(agent.uuid, runtime)

      updated = Agents.get_agent_by_uuid(agent.uuid)
      assert Agents.effective_status(updated) == :idle
    end
  end

  describe "effective_status/1" do
    test "returns :idle when agent recently touched" do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      assert Agents.effective_status(agent) == :idle
    end

    test "returns :lost_contact when updated_at older than threshold" do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      # Set updated_at to 100 seconds ago
      old = NaiveDateTime.add(NaiveDateTime.utc_now(), -100, :second)
      agent = %{agent | updated_at: old}

      assert Agents.effective_status(agent, lost_contact_seconds: 90) == :lost_contact
    end

    test "returns :disabled when agent disabled" do
      {:ok, agent} =
        Agents.register_agent(%{uuid: @valid_uuid, hostname: "agent", ipaddress: "192.168.1.1"})

      {:ok, disabled} = Agents.disable_agent(agent)
      assert Agents.effective_status(disabled) == :disabled
    end
  end

  describe "add_resources/2 and remove_resources/2" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent",
          ipaddress: "192.168.1.1",
          resources: ["linux"]
        })

      %{agent: agent}
    end

    test "adds resources to agent", %{agent: agent} do
      {:ok, updated} = Agents.add_resources(agent, ["docker", "nodejs"])
      assert updated.resources == ["linux", "docker", "nodejs"]
    end

    test "removes duplicates when adding resources", %{agent: agent} do
      {:ok, updated} = Agents.add_resources(agent, ["linux", "docker"])
      assert updated.resources == ["linux", "docker"]
    end

    test "removes resources from agent", %{agent: agent} do
      {:ok, updated} = Agents.remove_resources(agent, ["linux"])
      assert updated.resources == []
    end

    test "ignores non-existent resources when removing", %{agent: agent} do
      {:ok, updated} = Agents.remove_resources(agent, ["docker"])
      assert updated.resources == ["linux"]
    end
  end

  describe "add_environments/2 and remove_environments/2" do
    setup do
      {:ok, agent} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "agent",
          ipaddress: "192.168.1.1",
          environments: ["dev"]
        })

      %{agent: agent}
    end

    test "adds environments to agent", %{agent: agent} do
      {:ok, updated} = Agents.add_environments(agent, ["staging", "prod"])
      assert updated.environments == ["dev", "staging", "prod"]
    end

    test "removes duplicates when adding environments", %{agent: agent} do
      {:ok, updated} = Agents.add_environments(agent, ["dev", "staging"])
      assert updated.environments == ["dev", "staging"]
    end

    test "removes environments from agent", %{agent: agent} do
      {:ok, updated} = Agents.remove_environments(agent, ["dev"])
      assert updated.environments == []
    end
  end

  describe "find_agents_for_job/1" do
    setup do
      {:ok, agent1} =
        Agents.register_agent(%{
          uuid: "550e8400-e29b-41d4-a716-446655440001",
          hostname: "agent-1",
          ipaddress: "192.168.1.1",
          resources: ["linux", "docker"],
          environments: ["production"]
        })

      {:ok, agent2} =
        Agents.register_agent(%{
          uuid: "550e8400-e29b-41d4-a716-446655440002",
          hostname: "agent-2",
          ipaddress: "192.168.1.2",
          resources: ["windows"],
          environments: ["production"]
        })

      {:ok, agent3} =
        Agents.register_agent(%{
          uuid: "550e8400-e29b-41d4-a716-446655440003",
          hostname: "agent-3",
          ipaddress: "192.168.1.3",
          resources: ["linux", "docker"],
          environments: ["staging"]
        })

      {:ok, disabled_agent} =
        Agents.register_agent(%{
          uuid: "550e8400-e29b-41d4-a716-446655440004",
          hostname: "agent-4",
          ipaddress: "192.168.1.4",
          resources: ["linux", "docker"],
          environments: ["production"]
        })

      Agents.disable_agent(disabled_agent)

      %{agent1: agent1, agent2: agent2, agent3: agent3}
    end

    test "finds agents with matching resources and environment", %{agent1: agent1} do
      job_spec = %{resources: ["linux", "docker"], environment: "production"}
      agents = Agents.find_agents_for_job(job_spec)

      assert length(agents) == 1
      assert hd(agents).id == agent1.id
    end

    test "returns empty when no agents match resources", %{} do
      job_spec = %{resources: ["macos"], environment: "production"}
      agents = Agents.find_agents_for_job(job_spec)

      assert agents == []
    end

    test "returns empty when no agents in environment", %{} do
      job_spec = %{resources: ["linux", "docker"], environment: "development"}
      agents = Agents.find_agents_for_job(job_spec)

      assert agents == []
    end

    test "finds agents with matching resources when no environment specified", %{
      agent1: agent1,
      agent3: agent3
    } do
      job_spec = %{resources: ["linux", "docker"]}
      agents = Agents.find_agents_for_job(job_spec)

      assert length(agents) == 2
      agent_ids = Enum.map(agents, & &1.id)
      assert agent1.id in agent_ids
      assert agent3.id in agent_ids
    end

    test "excludes disabled agents", %{} do
      job_spec = %{resources: ["linux", "docker"], environment: "production"}
      agents = Agents.find_agents_for_job(job_spec)

      refute Enum.any?(agents, &(&1.disabled == true))
    end
  end

  describe "Agent.elastic?/1" do
    test "returns true when elastic_agent_id and elastic_plugin_id are set" do
      agent = %Agent{elastic_agent_id: "elastic-1", elastic_plugin_id: "plugin-1"}
      assert Agent.elastic?(agent) == true
    end

    test "returns false when elastic_agent_id is nil" do
      agent = %Agent{elastic_agent_id: nil, elastic_plugin_id: "plugin-1"}
      assert Agent.elastic?(agent) == false
    end

    test "returns false when elastic_plugin_id is nil" do
      agent = %Agent{elastic_agent_id: "elastic-1", elastic_plugin_id: nil}
      assert Agent.elastic?(agent) == false
    end
  end

  describe "Agent.enabled?/1" do
    test "returns true when not disabled" do
      agent = %Agent{disabled: false}
      assert Agent.enabled?(agent) == true
    end

    test "returns false when disabled" do
      agent = %Agent{disabled: true}
      assert Agent.enabled?(agent) == false
    end
  end

  describe "Agent.has_all_resources?/2" do
    test "returns true when agent has all required resources" do
      agent = %Agent{resources: ["linux", "docker", "nodejs"]}
      assert Agent.has_all_resources?(agent, ["linux", "docker"]) == true
    end

    test "returns false when agent missing some resources" do
      agent = %Agent{resources: ["linux"]}
      assert Agent.has_all_resources?(agent, ["linux", "docker"]) == false
    end

    test "returns true when no resources required" do
      agent = %Agent{resources: ["linux"]}
      assert Agent.has_all_resources?(agent, []) == true
    end
  end

  describe "Agent.in_environment?/2" do
    test "returns true when agent is in environment" do
      agent = %Agent{environments: ["production", "staging"]}
      assert Agent.in_environment?(agent, "production") == true
    end

    test "returns false when agent not in environment" do
      agent = %Agent{environments: ["staging"]}
      assert Agent.in_environment?(agent, "production") == false
    end
  end
end
