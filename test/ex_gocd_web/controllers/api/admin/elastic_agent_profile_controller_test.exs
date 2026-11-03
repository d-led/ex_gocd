defmodule ExGoCDWeb.API.Admin.ElasticAgentProfileControllerTest do
  @moduledoc """
  The elastic profile API at the path api.go.cd gives it. The interesting part is
  the shape: GoCD names a profile with the `id` its author chose and lists
  properties as pairs, where our rows carry a generated id and a map — so these
  tests drive the documented payloads and read the documented answers back.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.ElasticAgentProfiles

  @documented_profile %{
    "id" => "unit-tests",
    "cluster_profile_id" => "prod-cluster",
    "properties" => [
      %{"key" => "Image", "value" => "gocdcontrib/gocd-dev-build"},
      %{"key" => "MaxMemory", "value" => "4Gi"}
    ]
  }

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "elastic-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: conn |> Plug.Test.init_test_session(%{}) |> log_in_as(admin.username)}
  end

  describe "POST /go/api/elastic/profiles" do
    test "takes the profile as api.go.cd posts it, and answers with its id", %{conn: conn} do
      body = conn |> post("/go/api/elastic/profiles", @documented_profile) |> json_response(201)

      assert body["id"] == "unit-tests"
      assert body["cluster_profile_id"] == "prod-cluster"

      assert body["properties"] == [
               %{"key" => "Image", "value" => "gocdcontrib/gocd-dev-build"},
               %{"key" => "MaxMemory", "value" => "4Gi"}
             ]

      assert body["_links"]["self"]["href"] == "/api/elastic/profiles/unit-tests"
    end

    test "stores the listed properties so the scheduler can read them", %{conn: conn} do
      conn |> post("/go/api/elastic/profiles", @documented_profile) |> json_response(201)

      profile = ElasticAgentProfiles.find_profile("unit-tests")

      assert profile.properties == %{
               "Image" => "gocdcontrib/gocd-dev-build",
               "MaxMemory" => "4Gi"
             }
    end
  end

  describe "GET /go/api/elastic/profiles" do
    test "embeds the profiles it has", %{conn: conn} do
      {:ok, _} =
        ElasticAgentProfiles.create_profile(%{
          name: "listed",
          cluster_profile_id: "c1",
          properties: %{}
        })

      body = conn |> get("/go/api/elastic/profiles") |> json_response(200)

      assert [profile] = body["_embedded"]["profiles"]
      assert profile["id"] == "listed"
      assert profile["properties"] == []
    end
  end

  describe "GET /go/api/elastic/profiles/:profile_id" do
    test "finds a profile by the name it was given", %{conn: conn} do
      {:ok, _} =
        ElasticAgentProfiles.create_profile(%{
          name: "by-name",
          cluster_profile_id: "c1",
          properties: %{"Image" => "alpine"}
        })

      body = conn |> get("/go/api/elastic/profiles/by-name") |> json_response(200)

      assert body["id"] == "by-name"
      assert body["properties"] == [%{"key" => "Image", "value" => "alpine"}]
    end

    test "says a profile it cannot find is missing", %{conn: conn} do
      body = conn |> get("/go/api/elastic/profiles/absent") |> json_response(404)

      assert body["message"] =~ "absent"
    end
  end

  describe "PUT /go/api/elastic/profiles/:profile_id" do
    test "changes the properties it is given", %{conn: conn} do
      {:ok, _} =
        ElasticAgentProfiles.create_profile(%{
          name: "edited",
          cluster_profile_id: "c1",
          properties: %{"Image" => "alpine"}
        })

      body =
        conn
        |> put("/go/api/elastic/profiles/edited", %{
          "id" => "edited",
          "cluster_profile_id" => "c1",
          "properties" => [%{"key" => "Image", "value" => "busybox"}]
        })
        |> json_response(200)

      assert body["properties"] == [%{"key" => "Image", "value" => "busybox"}]
      assert ElasticAgentProfiles.find_profile("edited").properties == %{"Image" => "busybox"}
    end
  end

  describe "DELETE /go/api/elastic/profiles/:profile_id" do
    test "removes the profile", %{conn: conn} do
      {:ok, _} =
        ElasticAgentProfiles.create_profile(%{
          name: "doomed",
          cluster_profile_id: "c1",
          properties: %{}
        })

      conn = delete(conn, "/go/api/elastic/profiles/doomed")

      assert response(conn, 204)
      assert ElasticAgentProfiles.find_profile("doomed") == nil
    end
  end

  describe "the older spelling" do
    test "still creates a profile wrapped in elastic_agent_profile", %{conn: conn} do
      body =
        conn
        |> post("/api/admin/elastic_agent_profiles", %{
          "elastic_agent_profile" => %{"name" => "wrapped", "cluster_profile_id" => "c1"}
        })
        |> json_response(201)

      assert body["id"] == "wrapped"
    end
  end

  test "is refused to someone who is not an admin" do
    {:ok, member} =
      Accounts.create_user(%{
        username: "elastic-member-#{System.unique_integer([:positive])}",
        display_name: "Member",
        roles: [],
        status: "Active"
      })

    conn = build_conn() |> Plug.Test.init_test_session(%{}) |> log_in_as(member.username)

    assert conn |> get("/go/api/elastic/profiles") |> json_response(:forbidden)
  end
end
