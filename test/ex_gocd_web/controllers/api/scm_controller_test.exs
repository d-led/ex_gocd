defmodule ExGoCDWeb.API.SCMControllerTest do
  @moduledoc """
  `/api/admin/scms/:id` used the id as a position: `Enum.at(materials, id)`. So
  an SCM was never answered by its id — one id returned the SCM at that offset,
  the next id returned nothing — and any non-numeric id raised in
  `String.to_integer/1`.
  """
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures, only: [insert_material: 3, insert_pipeline: 2]

  alias ExGoCD.Accounts

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "scm-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, admin.username)}
  end

  describe "GET /go/api/admin/scms/:id" do
    test "answers the SCM the id names, wherever it sits in the list", %{conn: conn} do
      deploy = insert_pipeline("deploy", group: "shipping")
      build = insert_pipeline("build", group: "shipping")
      deploy_scm = insert_material(deploy, "git", "https://example.com/deploy.git")
      build_scm = insert_material(build, "git", "https://example.com/build.git")

      for scm <- [deploy_scm, build_scm] do
        body = conn |> get("/go/api/admin/scms/#{scm.id}") |> json_response(200)

        assert body["url"] == scm.url
      end
    end

    test "an SCM names the pipelines that use it", %{conn: conn} do
      deploy = insert_pipeline("deploy", group: "shipping")
      scm = insert_material(deploy, "git", "https://example.com/deploy.git")

      body = conn |> get("/go/api/admin/scms/#{scm.id}") |> json_response(200)

      assert body["pipelines"] == [%{"name" => "deploy", "group" => "shipping"}]
    end

    test "an id that is not a number is missing, not a crash", %{conn: conn} do
      conn = get(conn, "/go/api/admin/scms/not-a-number")

      assert json_response(conn, 404) == %{"error" => "SCM not found"}
    end

    test "an id nobody holds is missing", %{conn: conn} do
      conn = get(conn, "/go/api/admin/scms/999999")

      assert json_response(conn, 404) == %{"error" => "SCM not found"}
    end
  end

  describe "GET /go/api/admin/scms" do
    test "lists each SCM once, naming every pipeline that uses it", %{conn: conn} do
      deploy = insert_pipeline("deploy", group: "shipping")
      release = insert_pipeline("release", group: "shipping")
      shared = insert_material(deploy, "git", "https://example.com/shared.git")
      _same_scm_elsewhere = shared

      ExGoCD.Pipelines.add_material_to_pipeline(release, shared)

      body = conn |> get("/go/api/admin/scms") |> json_response(200)

      assert [scm] = body["materials"]
      assert scm["url"] == shared.url

      assert Enum.sort(Enum.map(scm["pipelines"], & &1["name"])) == ["deploy", "release"]
    end
  end
end
