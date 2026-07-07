defmodule ExGoCDWeb.API.Admin.PipelineGroupPermissionControllerTest do
  use ExGoCDWeb.ConnCase
  alias ExGoCD.{Repo, Accounts}

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        username: "delegated-admin-#{System.unique_integer()}",
        display_name: "DA",
        roles: ["admin"]
      })

    %{user: user}
  end

  test "grants and lists pipeline group permissions", %{conn: conn, user: user} do
    conn =
      conn
      |> log_in_as(user.username)
      |> post("/api/admin/pipeline_group_permissions", %{
        user_id: "#{user.id}",
        pipeline_group: "Build",
        role: "operator"
      })

    assert conn.status == 201

    assert %{"data" => %{"role" => "operator", "pipeline_group" => "Build"}} =
             json_response(conn, 201)

    list_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> log_in_as(user.username)
      |> get("/api/admin/pipeline_group_permissions?user_id=#{user.id}")

    assert list_conn.status == 200
    assert [%{"role" => "operator"}] = json_response(list_conn, 200)["data"]
  end

  test "revokes pipeline group permissions", %{conn: conn, user: user} do
    Accounts.grant_pipeline_group_permission(user.id, "Deploy", "viewer")

    conn =
      conn
      |> log_in_as(user.username)
      |> delete("/api/admin/pipeline_group_permissions?user_id=#{user.id}&pipeline_group=Deploy")

    assert conn.status == 200

    perms = Accounts.list_pipeline_group_permissions(user.id)
    assert [] = perms
  end

  test "rejects invalid role", %{conn: conn, user: user} do
    conn =
      conn
      |> log_in_as(user.username)
      |> post("/api/admin/pipeline_group_permissions", %{
        user_id: "#{user.id}",
        pipeline_group: "Build",
        role: "superadmin"
      })

    assert conn.status == 422
    assert %{"errors" => %{"role" => _}} = json_response(conn, 422)
  end
end
