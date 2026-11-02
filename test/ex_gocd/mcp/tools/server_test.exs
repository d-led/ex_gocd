defmodule ExGoCD.Mcp.Tools.ServerTest do
  @moduledoc """
  The four questions about the deployment itself.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Agents.Agent
  alias ExGoCD.AuditLog
  alias ExGoCD.MaintenanceMode
  alias ExGoCD.Mcp.Tools.Server, as: Tools
  alias ExGoCD.Repo

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "admin", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  describe "gocd_server_info" do
    test "reports the counts this server actually has" do
      insert_pipeline("one")
      insert_pipeline("two")
      Repo.insert!(%Agent{uuid: "a-1", hostname: "build-1", ipaddress: "10.0.0.1", state: "Idle"})

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_server_info", %{}, @ctx)

      assert structured["pipelines"] == 2
      assert structured["agents"]["total"] == 1
      assert structured["agents"]["by_state"]["Idle"] == 1
      assert structured["maintenance_mode"] == false
      assert text =~ "2 pipeline(s)"
    end

    test "says when the server is in maintenance mode" do
      MaintenanceMode.enable()
      on_exit(fn -> MaintenanceMode.disable() end)

      assert {:ok, %{structured: %{"maintenance_mode" => true}}} =
               Tools.call("gocd_server_info", %{}, @ctx)
    end
  end

  describe "gocd_dashboard" do
    test "shows each pipeline with the status of its latest run" do
      insert_pipeline("dash")
      instance = insert_pipeline_instance_by_name("dash", 1, DateTime.utc_now())
      insert_stage_instance(instance.id, "build", state: "Completed", result: "Failed")

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_dashboard", %{}, @ctx)

      assert structured["by_status"]["Failed"] == 1
      assert [%{"name" => "dash", "counter" => 1}] = structured["pipelines"]
      assert text =~ "dash"
    end
  end

  describe "gocd_audit_log" do
    test "finds entries by actor and action, newest first" do
      AuditLog.log("ops", "pipeline.paused",
        resource_type: "pipeline",
        resource_name: "freeze-me",
        details: %{"paused" => true}
      )

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_audit_log", %{"actor" => "ops"}, @ctx)

      assert [%{"actor" => "ops", "action" => "pipeline.paused"}] = structured["entries"]
      assert text =~ "freeze-me"
    end

    test "says so when nothing matches" do
      assert {:ok, %{text: "No audit entries match."}} =
               Tools.call("gocd_audit_log", %{"actor" => "nobody"}, @ctx)
    end
  end

  describe "gocd_queue" do
    test "reports an empty queue as empty, not as a missing answer" do
      assert {:ok, %{text: text, structured: structured}} = Tools.call("gocd_queue", %{}, @ctx)

      assert structured["pending"] == 0
      assert text =~ "0 pending"
    end
  end
end
