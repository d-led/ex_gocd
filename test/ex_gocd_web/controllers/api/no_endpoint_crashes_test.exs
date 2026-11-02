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
      ExGoCD.Sweep.assert_all_answered(@open_paths, &get(conn, &1))
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
      ExGoCD.Sweep.assert_all_answered(@admin_paths, &get(conn, &1))
    end

    test "is answered, not crashed, when the thing named is not there", %{conn: conn} do
      ExGoCD.Sweep.assert_all_answered(absent_paths(), &get(conn, &1))
    end
  end

  # Names that resolve to nothing, counters that parse, and ids of the right
  # shape but unknown. A route that names something absent has to say so; what it
  # must not do is fall over.
  defp absent_paths do
    uuid = Ecto.UUID.generate()

    [
      "/api/admin/artifact_stores/#{uuid}",
      "/api/admin/auth_configs/#{uuid}",
      "/api/admin/backups/999999",
      "/api/admin/cluster_profiles/#{uuid}",
      "/api/admin/elastic_agent_profiles/#{uuid}",
      "/api/admin/environments/absent",
      "/api/admin/package_repositories/#{uuid}",
      "/api/admin/packages/#{uuid}",
      "/api/admin/pipeline_groups/absent",
      "/api/admin/pipelines/absent",
      "/api/admin/plugin_settings/absent",
      "/api/admin/secret_configs/#{uuid}",
      "/api/admin/security/roles/absent",
      "/api/admin/templates/absent",
      "/api/agents/#{uuid}",
      "/api/analytics/nonsense",
      "/api/feeds/jobs/absent/1/absent/1/absent",
      "/api/feeds/materials/absent/1/absent",
      "/api/feeds/pipelines/absent/stages.xml",
      "/api/feeds/stages/absent/1/absent/1",
      "/api/jobs/absent/1/absent/1/absent",
      "/api/jobs/absent/absent/absent/history",
      "/api/pipelines/absent/1",
      "/api/pipelines/absent/history",
      "/api/pipelines/absent/status",
      "/api/stages/absent/1/absent/1",
      "/api/stages/absent/absent/history",
      "/api/users/absent",
      "/go/api/agent_health/#{uuid}",
      "/go/api/agents/#{uuid}",
      "/go/api/plugin_settings/absent",
      "/go/api/scms/absent"
    ]
  end
end
