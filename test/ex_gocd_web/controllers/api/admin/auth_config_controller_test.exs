defmodule ExGoCDWeb.API.Admin.AuthConfigControllerTest do
  @moduledoc """
  The auth config API had no tests and two faults.

  Its id is a uuid, and every action read it with `Repo.get/2`, so a path that
  was not a uuid raised `Ecto.Query.CastError` — a 500 for a mistyped path. And
  api.go.cd documents it at `/go/api/admin/security/auth_configs`, while ex_gocd
  served `/go/api/admin/auth_configs`: a client following the documentation got a
  404.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  @documented "/go/api/admin/security/auth_configs"

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "auth-config-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, admin.username)}
  end

  describe "an auth config nobody has" do
    test "is missing when read", %{conn: conn} do
      conn = get(conn, "#{@documented}/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["message"] =~ "not found"
    end

    test "a path that is not a uuid is missing too, not a crash", %{conn: conn} do
      conn = get(conn, "#{@documented}/not-a-uuid")

      assert json_response(conn, 404)["message"] =~ "not found"
    end
  end

  describe "the documented path" do
    test "creates a config and lists it", %{conn: conn} do
      created =
        conn
        |> post(@documented, %{
          "auth_config" => %{"plugin_id" => "ldap", "properties" => %{"url" => "ldap://x"}}
        })
        |> json_response(201)

      assert created["data"]["plugin_id"] == "ldap"

      listed = conn |> get(@documented) |> json_response(200)

      assert [%{"plugin_id" => "ldap"}] = listed["data"]
    end
  end

  describe "a config with no plugin" do
    test "is refused, naming the field", %{conn: conn} do
      body = conn |> post(@documented, %{"auth_config" => %{}}) |> json_response(422)

      assert Map.has_key?(body["errors"], "plugin_id")
    end
  end

  describe "deleting" do
    test "removes the config", %{conn: conn} do
      created =
        conn
        |> post(@documented, %{"auth_config" => %{"plugin_id" => "saml"}})
        |> json_response(201)

      id = created["data"]["id"]

      assert conn |> delete("#{@documented}/#{id}") |> response(204)

      assert conn |> get("#{@documented}/#{id}") |> json_response(404)
    end
  end
end
