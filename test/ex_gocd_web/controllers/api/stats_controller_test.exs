# Copyright 2026 ex_gocd
# Tests for Stats API.

defmodule ExGoCDWeb.API.StatsControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  describe "GET /api/stats and GET /go/api/stats" do
    test "returns 200 and stats payload", %{conn: conn} do
      for path <- ["/api/stats", "/go/api/stats"] do
        conn = get(conn, path)

        assert response = json_response(conn, 200)
        assert Map.has_key?(response, "agents")
        assert Map.has_key?(response, "jobs")
        assert Map.has_key?(response, "system")

        agents = response["agents"]
        assert Map.has_key?(agents, "total")
        assert Map.has_key?(agents, "idle")
        assert Map.has_key?(agents, "building")
        assert Map.has_key?(agents, "lost_contact")
        assert Map.has_key?(agents, "disabled")
        assert Map.has_key?(agents, "pending")

        jobs = response["jobs"]
        assert Map.has_key?(jobs, "pending")
        assert Map.has_key?(jobs, "running")

        system = response["system"]
        assert Map.has_key?(system, "uptime_seconds")
        assert Map.has_key?(system, "memory_total_bytes")
        assert Map.has_key?(system, "active_connections")
      end
    end
  end
end
