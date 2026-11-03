defmodule ExGoCDWeb.API.Admin.MaintenanceModeControllerTest do
  @moduledoc """
  The toggle is one flag for the whole server, so these tests cannot run beside
  others that trigger pipelines.
  """
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.Accounts
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents
  alias ExGoCD.MaintenanceMode

  import ExGoCDWeb.ConfirmHeader

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "maint-api-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    on_exit(fn -> MaintenanceMode.disable() end)

    %{conn: log_in_as(conn, admin.username)}
  end

  describe "GET /go/api/admin/maintenance_mode/enable" do
    test "turns maintenance mode on, as the documented curl does", %{conn: conn} do
      conn = get(conn, ~p"/go/api/admin/maintenance_mode/enable")

      assert %{"message" => message} = json_response(conn, 200)
      assert message =~ "enabled"
      assert MaintenanceMode.enabled?()
    end
  end

  describe "GET /go/api/admin/maintenance_mode/disable" do
    test "turns maintenance mode off", %{conn: conn} do
      {:ok, :enabled} = MaintenanceMode.enable()

      conn = get(conn, ~p"/go/api/admin/maintenance_mode/disable")

      assert %{"message" => message} = json_response(conn, 200)
      assert message =~ "disabled"
      refute MaintenanceMode.enabled?()
    end
  end

  describe "GET /go/api/admin/maintenance_mode/info" do
    test "reports whether the server is in maintenance mode", %{conn: conn} do
      {:ok, :enabled} = MaintenanceMode.enable()

      conn = get(conn, ~p"/go/api/admin/maintenance_mode/info")

      assert %{
               "_embedded" => %{
                 "is_maintenance_mode" => true,
                 "metadata" => %{"updated_by" => "admin"}
               }
             } = json_response(conn, 200)
    end

    test "names the work that keeps the server from entering maintenance", %{conn: conn} do
      uuid = register_agent()
      {:ok, run} = AgentJobRuns.create_run(uuid, "build-in-flight", "p", "s", "j")
      {:ok, _} = AgentJobRuns.report_status(run.agent_uuid, run.build_id, "Building")

      conn = get(conn, ~p"/go/api/admin/maintenance_mode/info")

      assert %{
               "_embedded" => %{
                 "attributes" => %{
                   "has_running_systems" => true,
                   "running_systems" => %{"running_jobs" => ["build-in-flight"]}
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "POST /go/api/admin/maintenance_mode/enable" do
    test "asks an empty request to confirm itself", %{conn: conn} do
      conn = post(conn, ~p"/go/api/admin/maintenance_mode/enable")

      assert_unconfirmed_request_refused(conn)
      refute ExGoCD.MaintenanceMode.enabled?()
    end
  end

  defp register_agent do
    uuid = Ecto.UUID.generate()

    {:ok, _} =
      Agents.register_agent(%{uuid: uuid, hostname: "maint-agent", ipaddress: "192.168.1.1"})

    uuid
  end
end
