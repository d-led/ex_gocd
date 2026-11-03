# Copyright 2026 ex_gocd
# Tests for GoCD Plugin Info API.

defmodule ExGoCDWeb.API.PluginInfoControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  @git_plugin "ex_gocd.scm.git"

  describe "GET /api/admin/plugin_info" do
    test "lists every built-in plugin with its health", %{conn: conn} do
      conn = get(conn, ~p"/api/admin/plugin_info")

      assert %{"plugins" => plugins} = json_response(conn, 200)

      assert Enum.map(plugins, & &1["id"]) ==
               ~w(ex_gocd.config_repo.gocd_yaml ex_gocd.scm.git ex_gocd.notification.stdout)

      assert Enum.all?(plugins, &(&1["status"]["state"] == "active"))
    end
  end

  describe "GET /api/admin/plugin_info/:plugin_id" do
    test "describes one plugin, its origin and the extension point it fills",
         %{conn: conn} do
      conn = get(conn, ~p"/api/admin/plugin_info/#{@git_plugin}")

      assert %{"id" => @git_plugin} = plugin = json_response(conn, 200)
      assert plugin["_links"]["self"]["href"] == "/api/admin/plugin_info/#{@git_plugin}"
      assert plugin["status"]["state"] == "active"
      assert plugin["about"]["name"] == "Git Material"
      assert plugin["extensions"] == [%{"type" => "scm"}]
    end

    test "a built-in plugin is bundled and has no file on disk", %{conn: conn} do
      conn = get(conn, ~p"/api/admin/plugin_info/#{@git_plugin}")

      assert %{"bundled_plugin" => true, "plugin_file_location" => nil} =
               json_response(conn, 200)
    end

    test "answers not found for an unknown plugin id", %{conn: conn} do
      conn = get(conn, ~p"/api/admin/plugin_info/no.such.plugin")

      assert %{"message" => message} = json_response(conn, :not_found)
      assert message =~ "no.such.plugin"
    end

    test "works with /go/api routing prefix", %{conn: conn} do
      conn = get(conn, ~p"/go/api/admin/plugin_info/#{@git_plugin}")

      assert %{"id" => @git_plugin} = json_response(conn, 200)
    end
  end
end
