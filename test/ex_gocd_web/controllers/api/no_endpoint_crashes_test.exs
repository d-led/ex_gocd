defmodule ExGoCDWeb.API.NoEndpointCrashesTest do
  @moduledoc """
  Every endpoint in the API answers something on an empty database — nothing
  reaches a 5xx because a row it expected is missing, or because the JSON it
  builds reads a field its schema does not have.

  This is the shape of test that found `/api/pipelines/:name/history` and
  `/api/pipelines/:name/:counter`, which had never returned a body: the code
  compiled, dialyzer was content, and only a request could tell. The list is the
  parameterless GET routes of both API trees; routes that take a path parameter
  are covered by their own controllers' tests.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  @open_paths [
    "/api/agents",
    "/api/analytics",
    "/api/analytics/agent_utilization",
    "/api/config/mailserver",
    "/api/dashboard",
    "/api/feeds/jobs/scheduled.xml",
    "/api/feeds/pipelines.xml",
    "/go/api/agent_health",
    "/go/api/agents",
    "/go/api/config/mailserver",
    "/go/api/plugin_info",
    "/go/api/server_health_messages",
    "/go/api/stats",
    "/go/api/v1/health",
    "/go/api/version"
  ]

  @admin_paths [
    "/api/admin/artifact_stores",
    "/api/admin/auth_configs",
    "/api/admin/cluster_profiles",
    "/api/admin/config.xml",
    "/api/admin/config/backup",
    "/api/admin/config/server/artifact_config",
    "/api/admin/config/server/default_job_timeout",
    "/api/admin/elastic_agent_profiles",
    "/api/admin/environments",
    "/api/admin/maintenance_mode/info",
    "/api/admin/notification_filters",
    "/api/admin/package_repositories",
    "/api/admin/packages",
    "/api/admin/pipeline_group_permissions",
    "/api/admin/pipeline_groups",
    "/api/admin/pipelines",
    "/api/admin/scms",
    "/api/admin/secret_configs",
    "/api/admin/security/system_admins",
    "/api/admin/site_url",
    "/api/admin/templates"
  ]

  describe "an unauthenticated caller" do
    test "is answered, not crashed, by every open endpoint", %{conn: conn} do
      Enum.each(@open_paths, fn path -> assert_answered(conn, path) end)
    end
  end

  describe "an admin" do
    setup %{conn: conn} do
      {:ok, admin} =
        Accounts.create_user(%{
          username: "smoke-admin-#{System.unique_integer([:positive])}",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      conn = conn |> Plug.Test.init_test_session(%{}) |> log_in_as(admin.username)
      %{conn: conn}
    end

    test "is answered, not crashed, by every admin endpoint", %{conn: conn} do
      Enum.each(@admin_paths, fn path -> assert_answered(conn, path) end)
    end
  end

  defp assert_answered(conn, path) do
    conn = get(conn, path)

    assert conn.status < 500,
           "#{path} answered #{conn.status}: #{String.slice(conn.resp_body || "", 0, 200)}"
  end
end
