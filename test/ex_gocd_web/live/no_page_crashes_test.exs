defmodule ExGoCDWeb.NoPageCrashesTest do
  @moduledoc """
  Every page mounts on an empty database.

  The API has a sweep like this one; pages need it more, because a page renders
  what several contexts return at once, and a field that does not exist or a list
  that is nil takes the whole page down rather than one endpoint. The tabs are
  listed one by one because a page is only as good as its worst tab.
  """
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ExGoCD.Accounts

  @open_pages [
    "/",
    "/pipelines",
    "/agents",
    "/materials",
    "/analytics",
    "/analytics/pipelines",
    "/analytics/agents",
    "/analytics/vsm"
  ]

  @admin_pages [
    "/admin",
    "/admin/agents",
    "/admin/artifact_stores",
    "/admin/audit_log",
    "/admin/auth_configs",
    "/admin/backup",
    "/admin/cluster_profiles",
    "/admin/config/server",
    "/admin/config_repos",
    "/admin/elastic_agents",
    "/admin/elastic_agent_configurations",
    "/admin/environments",
    "/admin/notification_filters",
    "/admin/observability",
    "/admin/package_repositories",
    "/admin/pipeline_group_permissions",
    "/admin/pipelines",
    "/admin/pipelines/new",
    "/admin/plugins",
    "/admin/scheduling",
    "/admin/scms",
    "/admin/secret_configs",
    "/admin/security",
    "/admin/security/auth_configs",
    "/admin/security/roles",
    "/admin/templates",
    "/admin/users",
    "/admin/config_repos/new",
    "/admin/package_repositories/new"
  ]

  describe "a visitor" do
    test "is shown every open page", %{conn: conn} do
      assert_all_mount(conn, @open_pages)
    end

    test "is answered by a page that names something absent", %{conn: conn} do
      assert_all_mount(conn, absent_paths())
    end
  end

  # A page told to show something that is not there has to say so. Counters
  # parse, names are ones nothing holds, ids are of the right shape.
  defp absent_paths do
    [
      "/agents/#{Ecto.UUID.generate()}/job_run_history",
      "/compare/absent",
      "/compare/absent/1/with/2",
      "/go/compare/absent/1/with/2",
      "/materials/value_stream_map/0000000000000000/abc123",
      "/pipeline/activity/absent",
      "/pipelines/absent/1/config_diff",
      "/pipelines/absent/1/build/1",
      "/pipelines/value_stream_map/absent/1",
      "/stage-duration/absent",
      "/tab/build/detail/absent/1/build/1/compile"
    ]
  end

  describe "an admin" do
    setup %{conn: conn} do
      {:ok, admin} =
        Accounts.create_user(%{
          username: "page-admin-#{System.unique_integer([:positive])}",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      conn = conn |> Plug.Test.init_test_session(%{}) |> log_in_as(admin.username)
      %{conn: conn}
    end

    test "is shown every admin page and tab", %{conn: conn} do
      assert_all_mount(conn, @admin_pages)
    end

    test "is answered by an admin page that names something absent", %{conn: conn} do
      assert_all_mount(conn, admin_absent_paths())
    end
  end

  defp admin_absent_paths do
    [
      "/admin/config_repos/#{Ecto.UUID.generate()}/edit",
      "/admin/pipelines/absent/edit/definition"
    ]
  end

  defp assert_all_mount(conn, paths) do
    ExGoCD.Sweep.assert_all_answered(paths, &live(conn, &1), &answered?/1)
  end

  # A page that sends the visitor elsewhere with a message has answered — that is
  # how a page says the thing it was asked for is not there. A redirect with
  # nothing to say has not.
  defp answered?({:ok, _view, _html}), do: true
  defp answered?({:error, {:redirect, %{flash: %{"error" => _}}}}), do: true
  defp answered?({:error, {:live_redirect, %{flash: %{"error" => _}}}}), do: true
  defp answered?(_other), do: false
end
