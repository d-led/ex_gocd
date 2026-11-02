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
  end

  # Mounts each page, keeping a note of the ones that raise, so one run names all
  # of them rather than the first.
  defp assert_all_mount(conn, paths) do
    offenders = paths |> Enum.map(&mount_result(conn, &1)) |> Enum.reject(&is_nil/1)

    assert offenders == [], "pages that did not mount:\n" <> Enum.join(offenders, "\n")
  end

  defp mount_result(conn, path) do
    case live(conn, path) do
      {:ok, _view, _html} -> nil
      {:error, reason} -> "#{path} answered #{inspect(reason)}"
    end
  rescue
    error -> "#{path} raised #{inspect(error.__struct__)}: #{Exception.message(error)}"
  end
end
