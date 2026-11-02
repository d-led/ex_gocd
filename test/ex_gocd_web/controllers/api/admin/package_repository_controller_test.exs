defmodule ExGoCDWeb.API.Admin.PackageRepositoryControllerTest do
  @moduledoc """
  Package repositories are documented at `/go/api/admin/repositories`, and their
  id is a uuid read with `Repo.get/2`: any path that is not a uuid raised
  `Ecto.Query.CastError` in all three actions that take an id.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  @documented "/go/api/admin/repositories"

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "repo-pkg-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, admin.username)}
  end

  describe "an id that is not a uuid" do
    test "is missing when read", %{conn: conn} do
      conn = get(conn, "#{@documented}/not-a-uuid")

      assert json_response(conn, 404)["message"] =~ "not found"
    end

    test "is missing when changed", %{conn: conn} do
      conn = put(conn, "#{@documented}/not-a-uuid", %{"package_repository" => %{}})

      assert json_response(conn, 404)["message"] =~ "not found"
    end

    test "is missing when deleted", %{conn: conn} do
      conn = delete(conn, "#{@documented}/not-a-uuid")

      assert json_response(conn, 404)["message"] =~ "not found"
    end
  end

  describe "the documented path" do
    test "creates a repository and lists it", %{conn: conn} do
      created =
        conn
        |> post(@documented, %{
          "package_repository" => %{
            "name" => "artifactory",
            "plugin_id" => "cd.go.artifact.docker"
          }
        })
        |> json_response(201)

      assert created["data"]["name"] == "artifactory"

      listed = conn |> get(@documented) |> json_response(200)

      assert [%{"name" => "artifactory"}] = listed["data"]
    end

    test "is also served at the older path, so neither client breaks", %{conn: conn} do
      conn
      |> post(@documented, %{
        "package_repository" => %{"name" => "nexus", "plugin_id" => "cd.go.artifact.maven"}
      })
      |> json_response(201)

      listed = conn |> get("/api/admin/package_repositories") |> json_response(200)

      assert [%{"name" => "nexus"}] = listed["data"]
    end
  end
end
