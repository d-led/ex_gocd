defmodule ExGoCDWeb.API.Admin.EnvironmentControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.Environments
  alias ExGoCD.Environments.Environment
  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo

  @valid_vars [
    %{"name" => "DB_PASSWORD", "value" => "secret", "secure" => true},
    %{"name" => "DB_USER", "value" => "postgres", "secure" => false}
  ]

  setup do
    # Clean up DB tables
    Repo.delete_all(Environment)
    Repo.delete_all(Pipeline)
    Repo.delete_all(Accounts.User)

    p1 = Repo.insert!(%Pipeline{name: "pipe-1", group: "default"})
    p2 = Repo.insert!(%Pipeline{name: "pipe-2", group: "default"})

    {:ok, p1: p1, p2: p2}
  end

  describe "Open Mode (No admin configured)" do
    test "allows any unauthenticated request to perform CRUD", %{conn: conn, p1: p1} do
      # Create
      create_conn =
        post(conn, ~p"/api/admin/environments", %{
          "name" => "dev-env",
          "pipelines" => [%{"name" => p1.name}],
          "environment_variables" => @valid_vars
        })

      assert json = json_response(create_conn, 201)
      assert json["name"] == "dev-env"
      assert length(json["pipelines"]) == 1
      assert hd(json["pipelines"])["name"] == p1.name

      # List
      list_conn = get(conn, ~p"/api/admin/environments")
      assert list_json = json_response(list_conn, 200)
      assert length(list_json["_embedded"]["environments"]) == 1

      # Show
      show_conn = get(conn, ~p"/api/admin/environments/dev-env")
      assert show_json = json_response(show_conn, 200)
      assert show_json["name"] == "dev-env"

      # Update
      etag = List.first(get_resp_header(show_conn, "etag"))

      update_conn =
        conn
        |> put_req_header("if-match", etag)
        |> put(~p"/api/admin/environments/dev-env", %{
          "pipelines" => %{"add" => [], "remove" => [p1.name]}
        })

      assert update_json = json_response(update_conn, 200)
      assert update_json["pipelines"] == []

      # Delete
      delete_conn = delete(conn, ~p"/api/admin/environments/dev-env")
      assert json_response(delete_conn, 200)
      assert Environments.get_environment_by_name("dev-env") == nil
    end
  end

  describe "Security Mode (Admin configured)" do
    setup do
      # Insert an admin user to activate security mode
      admin_user =
        Repo.insert!(%Accounts.User{
          username: "admin-user",
          display_name: "Admin User",
          roles: ["admin"],
          status: "Active"
        })

      # Insert a viewer user
      viewer_user =
        Repo.insert!(%Accounts.User{
          username: "viewer-user",
          display_name: "Viewer User",
          roles: ["viewer"],
          status: "Active"
        })

      {:ok, admin: admin_user, viewer: viewer_user}
    end

    test "allows admin full access", %{conn: conn, admin: admin, p1: p1} do
      # Log in as admin
      conn = log_in_as(conn, admin.username)

      # Create
      create_conn =
        post(conn, ~p"/api/admin/environments", %{
          "name" => "prod-env",
          "pipelines" => [%{"name" => p1.name}],
          "environment_variables" => @valid_vars
        })

      assert json_response(create_conn, 201)

      # Update
      show_conn = get(conn, ~p"/api/admin/environments/prod-env")
      etag = List.first(get_resp_header(show_conn, "etag"))

      update_conn =
        conn
        |> put_req_header("if-match", etag)
        |> put(~p"/api/admin/environments/prod-env", %{
          "pipelines" => []
        })

      assert json_response(update_conn, 200)

      # Delete
      delete_conn = delete(conn, ~p"/api/admin/environments/prod-env")
      assert json_response(delete_conn, 200)
    end

    test "allows viewer to read but denies write actions", %{conn: conn, viewer: viewer, p1: p1} do
      # Create an environment first using backend context
      {:ok, _env} =
        Environments.create_environment(%{
          "name" => "stage-env",
          "pipelines" => [%{"name" => p1.name}],
          "environment_variables" => @valid_vars
        })

      # Log in as viewer
      conn = log_in_as(conn, viewer.username)

      # Read actions (List & Show) should be allowed
      list_conn = get(conn, ~p"/api/admin/environments")
      assert json_response(list_conn, 200)

      show_conn = get(conn, ~p"/api/admin/environments/stage-env")
      assert json_response(show_conn, 200)
      etag = List.first(get_resp_header(show_conn, "etag"))

      # Write actions should be forbidden (403)
      create_conn = post(conn, ~p"/api/admin/environments", %{"name" => "new-env"})
      assert json_response(create_conn, 403)

      update_conn =
        conn
        |> put_req_header("if-match", etag)
        |> put(~p"/api/admin/environments/stage-env", %{"pipelines" => []})

      assert json_response(update_conn, 403)

      delete_conn = delete(conn, ~p"/api/admin/environments/stage-env")
      assert json_response(delete_conn, 403)
    end

    test "denies anonymous guest access to read and write", %{conn: conn} do
      # Anonymous request (without log_in_as)
      assert get(conn, ~p"/api/admin/environments") |> json_response(403)
      assert get(conn, ~p"/api/admin/environments/stage-env") |> json_response(403)

      assert post(conn, ~p"/api/admin/environments", %{"name" => "anon-env"})
             |> json_response(403)
    end

    test "returns 412 Precondition Failed on ETag mismatch", %{conn: conn, admin: admin, p1: p1} do
      {:ok, _env} =
        Environments.create_environment(%{
          "name" => "precondition-env",
          "pipelines" => [%{"name" => p1.name}],
          "environment_variables" => @valid_vars
        })

      conn = log_in_as(conn, admin.username)

      update_conn =
        conn
        |> put_req_header("if-match", "\"bad-etag\"")
        |> put(~p"/api/admin/environments/precondition-env", %{
          "pipelines" => []
        })

      assert json_response(update_conn, 412)
    end
  end
end
