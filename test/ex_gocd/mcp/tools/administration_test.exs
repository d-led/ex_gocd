defmodule ExGoCD.Mcp.Tools.AdministrationTest do
  @moduledoc """
  The operational tools: what they refuse without a confirmation, what they
  refuse without an administrator, and what they never print.
  """

  use ExGoCD.DataCase, async: false

  alias ExGoCD.AuditLog
  alias ExGoCD.ConfigRepos
  alias ExGoCD.MaintenanceMode
  alias ExGoCD.Mcp.Tools.Administration, as: Tools

  @admin %{username: "admin", display_name: "Admin", roles: ["admin"], status: "Active"}
  @viewer %{username: "viewer", display_name: "Viewer", roles: [], status: "Active"}

  setup do
    {:ok, _} = ExGoCD.Accounts.create_user(@admin)
    {:ok, _} = ExGoCD.Accounts.create_user(@viewer)

    on_exit(fn -> MaintenanceMode.disable() end)

    ctx = fn user -> %{user: user, base_url: "http://localhost:4000", remote_ip: "127.0.0.1"} end

    {:ok,
     admin: ctx.(struct(ExGoCD.Accounts.User, @admin)),
     viewer: ctx.(struct(ExGoCD.Accounts.User, @viewer))}
  end

  describe "gocd_set_maintenance_mode" do
    test "asks for a confirmation before it stops scheduling", %{admin: ctx} do
      assert {:error, message} =
               Tools.call("gocd_set_maintenance_mode", %{"enabled" => true}, ctx)

      assert message =~ "confirm: true"
      refute MaintenanceMode.enabled?()
    end

    test "turns it on when confirmed, and records who did it", %{admin: ctx} do
      assert {:ok, %{structured: %{"maintenance_mode" => true}}} =
               Tools.call(
                 "gocd_set_maintenance_mode",
                 %{"enabled" => true, "confirm" => true},
                 ctx
               )

      assert MaintenanceMode.enabled?()

      assert [entry | _] = AuditLog.search(%{action: "admin.maintenance_mode"})
      assert entry.actor == "admin"
    end

    test "turns it off without a confirmation — resuming needs no ceremony", %{admin: ctx} do
      MaintenanceMode.enable()

      assert {:ok, %{structured: %{"maintenance_mode" => false}}} =
               Tools.call("gocd_set_maintenance_mode", %{"enabled" => false}, ctx)

      refute MaintenanceMode.enabled?()
    end

    test "is an administrator's act", %{viewer: ctx} do
      assert {:error, message} =
               Tools.call(
                 "gocd_set_maintenance_mode",
                 %{"enabled" => true, "confirm" => true},
                 ctx
               )

      assert message =~ "Only an administrator"
      refute MaintenanceMode.enabled?()
    end
  end

  describe "gocd_backup_status and gocd_create_backup" do
    test "the status is a real answer even when nothing has run", %{admin: ctx} do
      assert {:ok, %{structured: %{"status" => status}}} =
               Tools.call("gocd_backup_status", %{}, ctx)

      assert is_binary(status)
    end

    test "starting a backup is an administrator's act", %{viewer: ctx} do
      assert {:error, message} = Tools.call("gocd_create_backup", %{}, ctx)
      assert message =~ "Only an administrator"
    end
  end

  describe "gocd_config_repos" do
    test "names a repository's configuration keys without printing its values", %{admin: ctx} do
      {:ok, _} =
        ConfigRepos.create_config_repo(%{
          "url" => "https://example.test/pipelines.git",
          "branch" => "main",
          "source_type" => "gocd_pipeline",
          "configuration" => %{"username" => "ci", "password" => "hunter2"}
        })

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_config_repos", %{}, ctx)

      assert [repository] = structured["config_repos"]
      assert repository["configuration_keys"] == ["password", "username"]
      refute text =~ "hunter2"
    end

    test "says what it means when there are none", %{admin: ctx} do
      assert {:ok, %{text: text}} = Tools.call("gocd_config_repos", %{}, ctx)
      assert text =~ "No config repositories"
    end
  end

  describe "gocd_list_users" do
    test "lists accounts with their roles, filtered by role", %{admin: ctx} do
      assert {:ok, %{structured: structured}} =
               Tools.call("gocd_list_users", %{"role" => "admin"}, ctx)

      assert [%{"username" => "admin", "roles" => ["admin"]}] = structured["users"]
    end

    test "is an administrator's act — the list says who to disable", %{viewer: ctx} do
      assert {:error, message} = Tools.call("gocd_list_users", %{}, ctx)
      assert message =~ "Only an administrator"
    end
  end
end
