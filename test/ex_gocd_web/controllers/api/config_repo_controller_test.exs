# Copyright 2026 ex_gocd
# Tests for ConfigRepoController — cleanup_test_data action.

defmodule ExGoCDWeb.API.ConfigRepoControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.{Repo, ConfigRepos.ConfigRepo}

  setup do
    Repo.delete_all(ConfigRepo)
    :ok
  end

  describe "DELETE /api/admin/config_repos/cleanup" do
    test "deletes config repos with eci-test URLs and returns count", %{conn: conn} do
      # Given: two matching repos, one non-matching
      Repo.insert!(%ConfigRepo{
        url: "https://github.com/eci-test/my-pipelines.git",
        plugin_id: "json.config.plugin"
      })

      Repo.insert!(%ConfigRepo{
        url: "https://github.com/eci-test/other-pipelines.git",
        plugin_id: "yaml.config.plugin"
      })

      Repo.insert!(%ConfigRepo{
        url: "https://github.com/production/pipelines.git",
        plugin_id: "json.config.plugin"
      })

      # When
      conn = delete(conn, "/api/admin/config_repos/cleanup")

      # Then
      assert response = json_response(conn, 200)
      assert response["deleted"] == 2

      # Verify only non-matching remains
      remaining = Repo.all(ConfigRepo)
      assert length(remaining) == 1
      assert hd(remaining).url == "https://github.com/production/pipelines.git"
    end

    test "returns deleted: 0 when no matching repos exist", %{conn: conn} do
      # Given: only a non-matching repo
      Repo.insert!(%ConfigRepo{
        url: "https://github.com/my-org/pipelines.git",
        plugin_id: "json.config.plugin"
      })

      # When
      conn = delete(conn, "/api/admin/config_repos/cleanup")

      # Then
      assert response = json_response(conn, 200)
      assert response["deleted"] == 0

      # Verify repo is untouched
      remaining = Repo.all(ConfigRepo)
      assert length(remaining) == 1
    end

    test "returns deleted: 0 when table is empty", %{conn: conn} do
      # When
      conn = delete(conn, "/api/admin/config_repos/cleanup")

      # Then
      assert response = json_response(conn, 200)
      assert response["deleted"] == 0
    end
  end
end
