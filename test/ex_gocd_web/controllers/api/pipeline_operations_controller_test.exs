defmodule ExGoCDWeb.API.PipelineOperationsControllerTest do
  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  setup %{conn: conn} do
    # Clean up DB before each test
    Repo.delete_all(Pipelines.Pipeline)
    Repo.delete_all(ExGoCD.Accounts.User)

    # Initialize session map on conn so get_session plug works
    conn = Plug.Test.init_test_session(conn, %{})

    {:ok, conn: conn}
  end

  describe "POST /api/pipelines/:pipeline_name/pause" do
    test "pauses pipeline successfully in open mode", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-pause", group: "test"})

      conn = post(conn, ~p"/api/pipelines/#{pipeline.name}/pause", %{"pause_cause" => "debugging failure"})

      assert response = json_response(conn, 200)
      assert response["message"] == "Pipeline 'test-api-pause' paused successfully."

      # Verify database state
      updated = Repo.get!(Pipelines.Pipeline, pipeline.id)
      assert updated.paused == true
      assert updated.paused_by == "guest"
      assert updated.pause_cause == "debugging failure"
      assert updated.paused_at != nil
    end

    test "requires admin/developer permissions when security is active", %{conn: conn} do
      # Seed users
      {:ok, _} = ExGoCD.Accounts.create_user(%{username: "admin", display_name: "Admin", roles: ["admin"], status: "Active"})
      {:ok, _} = ExGoCD.Accounts.create_user(%{username: "viewer", display_name: "Viewer", roles: [], status: "Active"})

      pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-api-auth-pause", group: "test"})

      # Try as viewer - forbidden
      viewer_conn = log_in_as(conn, "viewer")
      viewer_conn = post(viewer_conn, ~p"/api/pipelines/#{pipeline.name}/pause", %{"pause_cause" => "downtime"})
      assert json_response(viewer_conn, 403) == %{"error" => "Forbidden"}

      # Try as admin - works
      admin_conn = log_in_as(conn, "admin")
      admin_conn = post(admin_conn, ~p"/api/pipelines/#{pipeline.name}/pause", %{"pause_cause" => "downtime"})
      assert response = json_response(admin_conn, 200)
      assert response["message"] == "Pipeline 'test-api-auth-pause' paused successfully."
    end

    test "returns 404 for non-existent pipeline", %{conn: conn} do
      conn = post(conn, ~p"/api/pipelines/nonexistent-pipeline/pause", %{"pause_cause" => "test"})
      assert json_response(conn, 404) == %{"error" => "Pipeline 'nonexistent-pipeline' not found."}
    end
  end

  describe "POST /api/pipelines/:pipeline_name/unpause" do
    test "unpauses pipeline successfully", %{conn: conn} do
      # Create an already paused pipeline
      pipeline = Repo.insert!(%Pipelines.Pipeline{
        name: "test-api-unpause",
        group: "test",
        paused: true,
        paused_by: "someone",
        pause_cause: "reason",
        paused_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      conn = post(conn, ~p"/api/pipelines/#{pipeline.name}/unpause")

      assert response = json_response(conn, 200)
      assert response["message"] == "Pipeline 'test-api-unpause' unpaused successfully."

      # Verify database state
      updated = Repo.get!(Pipelines.Pipeline, pipeline.id)
      assert updated.paused == false
      assert updated.paused_by == nil
      assert updated.pause_cause == nil
      assert updated.paused_at == nil
    end

    test "works with /go/api routing prefix", %{conn: conn} do
      pipeline = Repo.insert!(%Pipelines.Pipeline{
        name: "test-go-api-unpause",
        group: "test",
        paused: true,
        paused_by: "someone",
        pause_cause: "reason",
        paused_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      conn = post(conn, ~p"/go/api/pipelines/#{pipeline.name}/unpause")

      assert response = json_response(conn, 200)
      assert response["message"] == "Pipeline 'test-go-api-unpause' unpaused successfully."
    end
  end
end
