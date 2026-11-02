defmodule ExGoCDWeb.API.Admin.ConfigRepoControllerTest do
  @moduledoc """
  A config repo is named in the path, and every action read the name with
  `Repo.get/2`: an id that was not a number raised `Ecto.Query.CastError`, so a
  mistyped path answered 500 in all four actions.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.ConfigRepos

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "repo-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, admin.username)}
  end

  describe "a config repo named by something that is not a number" do
    test "is missing when read", %{conn: conn} do
      conn = get(conn, "/go/api/admin/config_repos/absent-repo")

      assert json_response(conn, 404) == %{"error" => "Config repo not found"}
    end

    test "is missing when changed", %{conn: conn} do
      conn = put(conn, "/go/api/admin/config_repos/absent-repo", %{"branch" => "main"})

      assert json_response(conn, 404) == %{"error" => "Config repo not found"}
    end

    test "is missing when deleted", %{conn: conn} do
      conn = delete(conn, "/go/api/admin/config_repos/absent-repo")

      assert json_response(conn, 404) == %{"error" => "Config repo not found"}
    end
  end

  describe "GET /go/api/admin/config_repos" do
    test "lists a repository that exists", %{conn: conn} do
      {:ok, _repo} = ConfigRepos.create_config_repo(%{url: "https://example.com/config.git"})

      body = conn |> get("/go/api/admin/config_repos") |> json_response(200)

      assert [repo] = body["config_repos"]
      assert repo["url"] == "https://example.com/config.git"
    end
  end

  describe "GET /go/api/admin/config_repos/:id" do
    test "answers the repository with that id", %{conn: conn} do
      {:ok, repo} = ConfigRepos.create_config_repo(%{url: "https://example.com/config.git"})

      body = conn |> get("/go/api/admin/config_repos/#{repo.id}") |> json_response(200)

      assert body["config_repo"]["id"] == repo.id
    end
  end

  describe "POST /go/api/admin/config_repos" do
    test "refuses a repository with no url, naming the field", %{conn: conn} do
      body = conn |> post("/go/api/admin/config_repos", %{}) |> json_response(422)

      assert body["error"] == "Validation failed"
      assert Map.has_key?(body["details"], "url")
    end
  end

  describe "PUT /go/api/admin/config_repos/:id" do
    test "changes what the body names and keeps the rest", %{conn: conn} do
      {:ok, repo} =
        ConfigRepos.create_config_repo(%{url: "https://example.com/config.git"})

      body =
        conn
        |> put("/go/api/admin/config_repos/#{repo.id}", %{"branch" => "release"})
        |> json_response(200)

      assert body["config_repo"]["branch"] == "release"
      assert body["config_repo"]["url"] == "https://example.com/config.git"
    end
  end
end
