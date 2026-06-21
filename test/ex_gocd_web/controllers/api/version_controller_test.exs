# Copyright 2026 ex_gocd
# Tests for GoCD Version API.

defmodule ExGoCDWeb.API.VersionControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  describe "GET /api/version" do
    test "returns version information", %{conn: conn} do
      conn = get(conn, ~p"/api/version")
      assert response = json_response(conn, 200)

      assert response["version"] == "25.4.0"
      assert response["build_number"] == "21793"
      assert response["git_sha"] == "c8358258163d7b9833ab3b1b18a2f459999936b03a"
      assert response["full_version"] =~ "25.4.0"
      assert response["commit_url"] =~ "c8358258163d7b9833ab3b1b18a2f459999936b03a"
      assert response["_links"]["self"]["href"] == "/go/api/version"
    end

    test "works with /go/api routing prefix", %{conn: conn} do
      conn = get(conn, ~p"/go/api/version")
      assert response = json_response(conn, 200)
      assert response["version"] == "25.4.0"
    end
  end
end
