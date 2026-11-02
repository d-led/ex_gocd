defmodule ExGoCDWeb.API.Admin.ArtifactStoreControllerTest do
  @moduledoc """
  One of six admin controllers that answered an unknown id with a 500: the fetch
  went through `get_store!/1`, so a client that mistyped an id got a stack trace.
  The same shape is tested here for all three actions that take an id, and the
  other five controllers are held to it by the sweep in
  `no_endpoint_crashes_test.exs`.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.ArtifactStores

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "store-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    conn = conn |> Plug.Test.init_test_session(%{}) |> log_in_as(admin.username)
    %{conn: conn}
  end

  describe "an id nothing holds" do
    test "is missing when read", %{conn: conn} do
      id = Ecto.UUID.generate()

      body = conn |> get("/api/admin/artifact_stores/#{id}") |> json_response(404)

      assert body["message"] =~ id
    end

    test "is missing when changed", %{conn: conn} do
      id = Ecto.UUID.generate()

      body =
        conn
        |> patch("/api/admin/artifact_stores/#{id}", %{"artifact_store" => %{"id" => "renamed"}})
        |> json_response(404)

      assert body["message"] =~ id
    end

    test "is missing when deleted", %{conn: conn} do
      id = Ecto.UUID.generate()

      body = conn |> delete("/api/admin/artifact_stores/#{id}") |> json_response(404)

      assert body["message"] =~ id
    end
  end

  describe "a store that exists" do
    setup do
      {:ok, store} =
        ArtifactStores.create_store(%{
          "id" => "team-store",
          "plugin_id" => "cd.go.artifact.docker"
        })

      %{store: store}
    end

    test "is described by id", %{conn: conn, store: store} do
      body = conn |> get("/api/admin/artifact_stores/#{store.id}") |> json_response(200)

      assert body["data"]["id"] == store.id
      assert body["data"]["plugin_id"] == "cd.go.artifact.docker"
    end
  end
end
