defmodule ExGoCDWeb.DocumentedAdminPathsTest do
  @moduledoc """
  api.go.cd names the path of every admin resource, and ex_gocd has served some of
  them under a path of its own choosing: config repos, the backup settings, the
  role config API and the auth config API were each documented at a `go`-prefixed
  path that the router did not have, so a client written against the documentation
  got a 404. Elastic cluster profiles and package repositories were the same.

  This names the resources we implement and the path the documentation gives them,
  and asks each for a listing. Adding a resource means adding a line here.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  @documented [
    "/go/api/admin/security/roles",
    "/go/api/admin/security/auth_configs",
    "/go/api/admin/elastic/cluster_profiles",
    "/go/api/admin/repositories",
    "/go/api/admin/config_repos",
    "/go/api/admin/pipeline_groups",
    "/go/api/admin/environments",
    "/go/api/admin/templates",
    "/go/api/config/backup",
    "/go/api/admin/config.xml"
  ]

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "documented-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, admin.username)}
  end

  test "every documented admin path answers", %{conn: conn} do
    unserved =
      for path <- @documented,
          status = conn |> get(path) |> Map.fetch!(:status),
          status >= 400,
          do: "#{path} → #{status}"

    assert unserved == []
  end
end
