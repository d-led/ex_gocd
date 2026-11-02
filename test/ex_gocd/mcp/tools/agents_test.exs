defmodule ExGoCD.Mcp.Tools.AgentsTest do
  @moduledoc """
  The agents family: capacity as a number, and the two changes that need an
  administrator and a confirmation.
  """

  use ExGoCD.DataCase, async: false

  alias ExGoCD.Agents.Agent
  alias ExGoCD.AuditLog
  alias ExGoCD.Mcp.Tools.Agents, as: Tools
  alias ExGoCD.Repo

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "admin", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  @viewer %{@ctx | user: %ExGoCD.Accounts.User{username: "viewer", roles: [], status: "Active"}}

  setup do
    # An administrator exists, so the server is not in open mode: the permission
    # checks have something to check against.
    {:ok, _admin} =
      ExGoCD.Accounts.create_user(%{
        username: "admin",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    insert_agent("idle-1", state: "Idle", resources: ["linux", "docker"])
    insert_agent("busy-1", state: "Building")
    insert_agent("off-1", state: "Idle", disabled: true)
    :ok
  end

  describe "gocd_list_agents" do
    test "counts the states and says how much capacity is free" do
      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_list_agents", %{}, @ctx)

      assert structured["total"] == 3
      assert structured["idle_enabled"] == 1
      assert text =~ "Idle 2"
    end

    test "filters by state, by a required resource, and by disabled" do
      assert {:ok, %{structured: %{"matched" => 1}}} =
               Tools.call("gocd_list_agents", %{"resource" => "docker"}, @ctx)

      assert {:ok, %{structured: %{"matched" => 1}}} =
               Tools.call("gocd_list_agents", %{"status" => "disabled"}, @ctx)

      assert {:ok, %{structured: %{"matched" => 1}}} =
               Tools.call("gocd_list_agents", %{"status" => "Building"}, @ctx)
    end
  end

  describe "gocd_update_agent" do
    test "disabling an agent is recorded with the actor" do
      assert {:ok, %{structured: %{"agent" => agent}}} =
               Tools.call(
                 "gocd_update_agent",
                 %{"uuid" => "idle-1", "state" => "disabled"},
                 @ctx
               )

      assert agent["disabled"] == true

      assert [entry | _] = AuditLog.search(%{action: "agent.disabled"})
      assert entry.actor == "admin"
      assert entry.resource_name == "idle-1"
    end

    test "re-tagging an agent replaces only the list it names" do
      assert {:ok, %{structured: %{"agent" => agent}}} =
               Tools.call(
                 "gocd_update_agent",
                 %{"uuid" => "busy-1", "resources" => ["windows"]},
                 @ctx
               )

      assert agent["resources"] == ["windows"]
      assert agent["environments"] == []
    end

    test "a caller who is not an administrator is told why" do
      assert {:error, message} =
               Tools.call(
                 "gocd_update_agent",
                 %{"uuid" => "idle-1", "state" => "disabled"},
                 @viewer
               )

      assert message =~ "Only an administrator"
    end

    test "says when there is nothing to change" do
      assert {:error, message} = Tools.call("gocd_update_agent", %{"uuid" => "idle-1"}, @ctx)
      assert message =~ "Nothing to change"
    end
  end

  describe "gocd_kill_agent_tasks" do
    test "asks for a confirmation first" do
      assert {:error, message} =
               Tools.call("gocd_kill_agent_tasks", %{"uuid" => "busy-1"}, @ctx)

      assert message =~ "confirm: true"
    end

    test "says an idle agent has nothing to cancel" do
      assert {:error, message} =
               Tools.call("gocd_kill_agent_tasks", %{"uuid" => "idle-1", "confirm" => true}, @ctx)

      assert message =~ "no running tasks"
    end
  end

  defp insert_agent(uuid, opts) do
    Repo.insert!(%Agent{
      uuid: uuid,
      hostname: opts[:hostname] || uuid,
      ipaddress: "10.0.0.1",
      state: Keyword.get(opts, :state, "Idle"),
      resources: Keyword.get(opts, :resources, []),
      environments: Keyword.get(opts, :environments, []),
      disabled: Keyword.get(opts, :disabled, false)
    })
  end
end
