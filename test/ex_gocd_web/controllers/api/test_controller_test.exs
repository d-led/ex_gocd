# Copyright 2026 ex_gocd
# Tests for TestController.

defmodule ExGoCDWeb.API.TestControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.TestAgentSupervisor
  alias ExGoCDWeb.AgentPresence

  setup do
    TestAgentSupervisor.stop_all_agents()

    on_exit(fn ->
      TestAgentSupervisor.stop_all_agents()
    end)

    :ok
  end

  describe "POST /api/test/start_agents" do
    test "spawns N agents and returns success", %{conn: conn} do
      conn = post(conn, "/api/test/start_agents", %{"count" => "5"})

      assert response = json_response(conn, 200)
      assert response["message"] == "Started 5 simulated agents."

      # Verify presence
      presence = AgentPresence.list("agent")
      assert map_size(presence) == 5

      # Clean up synchronously
      TestAgentSupervisor.stop_all_agents()
    end
  end

  describe "POST /api/test/start_http_agents" do
    test "spawns N HTTP agents and returns success", %{conn: conn} do
      conn = post(conn, "/api/test/start_http_agents", %{"count" => "2"})

      assert response = json_response(conn, 200)
      assert response["message"] == "Started 2 HTTP simulated agents."

      # Verify supervisor started the processes
      children = DynamicSupervisor.which_children(TestAgentSupervisor)
      assert length(children) == 2
    end
  end
end
