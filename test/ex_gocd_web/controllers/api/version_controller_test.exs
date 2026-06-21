# Copyright 2026 ex_gocd
# Tests for GoCD Version API.

defmodule ExGoCDWeb.API.VersionControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  describe "GET /api/version" do
    test "returns version information", %{conn: conn} do
      conn = get(conn, ~p"/api/version")
      assert response = json_response(conn, 200)

    assert response["version"] == "0.1.0"
    assert response["build_number"] == "0.1.0"
    assert response["full_version"] =~ "0.1.0"
    assert response["commit_url"] =~ "github.com/d-led/ex_gocd/commits"
      assert response["_links"]["self"]["href"] == "/go/api/version"
    end

    test "works with /go/api routing prefix", %{conn: conn} do
      conn = get(conn, ~p"/go/api/version")
      assert response = json_response(conn, 200)
      assert response["version"] == "0.1.0"
    end
  end
end
