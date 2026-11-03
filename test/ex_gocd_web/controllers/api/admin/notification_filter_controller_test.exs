defmodule ExGoCDWeb.API.Admin.NotificationFilterControllerTest do
  use ExGoCDWeb.ConnCase

  alias ExGoCD.Accounts

  setup do
    {:ok, user} = Accounts.create_user(%{username: "notifytest", display_name: "Notify Test"})
    %{user: user}
  end

  describe "GET /api/admin/notification_filters" do
    test "returns empty list when no filters", %{conn: conn, user: user} do
      conn = get(conn, "/api/admin/notification_filters?user_id=#{user.id}")
      assert conn.status == 200
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns filters for user", %{conn: conn, user: user} do
      ExGoCD.Notifications.create_filter(%{
        user_id: user.id,
        pipeline_name: "demo",
        stage_name: "build",
        event: "fails"
      })

      conn = get(conn, "/api/admin/notification_filters?user_id=#{user.id}")
      assert conn.status == 200

      assert %{
               "data" => [
                 %{"pipeline_name" => "demo", "stage_name" => "build", "event" => "fails"}
               ]
             } =
               json_response(conn, 200)
    end

    test "asks for a user_id when none is given", %{conn: conn} do
      body = conn |> get("/api/admin/notification_filters") |> json_response(400)

      assert body["message"] =~ "user_id"
    end

    test "answers a user_id that is not a number as a bad request", %{conn: conn} do
      body =
        conn
        |> get("/api/admin/notification_filters?user_id=somebody")
        |> json_response(400)

      assert body["message"] =~ "whole number"
    end
  end

  describe "POST /api/admin/notification_filters" do
    test "creates a notification filter", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/admin/notification_filters", %{
          notification_filter: %{
            user_id: user.id,
            pipeline_name: "demo",
            stage_name: "build",
            event: "fails"
          }
        })

      assert conn.status == 201
      assert %{"data" => %{"pipeline_name" => "demo"}} = json_response(conn, 201)
    end

    test "rejects invalid event", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/admin/notification_filters", %{
          notification_filter: %{
            user_id: user.id,
            pipeline_name: "demo",
            stage_name: "build",
            event: "invalid"
          }
        })

      assert conn.status == 422
    end

    test "says what is missing when the body has no filter in it", %{conn: conn} do
      body =
        conn
        |> post("/api/admin/notification_filters", %{"unrelated" => true})
        |> json_response(400)

      assert body["message"] =~ "notification_filter"
    end
  end

  describe "DELETE /api/admin/notification_filters/:id" do
    test "says a filter it cannot find is missing", %{conn: conn} do
      body =
        conn
        |> delete("/api/admin/notification_filters/#{Ecto.UUID.generate()}")
        |> json_response(404)

      assert body["message"] =~ "not found"
    end

    test "says an id that is not an id is missing", %{conn: conn} do
      conn = delete(conn, "/api/admin/notification_filters/not-an-id")

      assert conn.status == 404
    end

    test "deletes a filter", %{conn: conn, user: user} do
      {:ok, filter} =
        ExGoCD.Notifications.create_filter(%{
          user_id: user.id,
          pipeline_name: "demo",
          stage_name: "build",
          event: "fails"
        })

      conn = delete(conn, "/api/admin/notification_filters/#{filter.id}")
      assert conn.status == 200

      conn2 = get(conn, "/api/admin/notification_filters?user_id=#{user.id}")
      assert %{"data" => []} = json_response(conn2, 200)
    end
  end

  describe "dispatch/5" do
    test "matches filters by pipeline, stage, and event" do
      {:ok, user} =
        Accounts.create_user(%{username: "dispatchtest", display_name: "Dispatch Test"})

      ExGoCD.Notifications.create_filter(%{
        user_id: user.id,
        pipeline_name: "demo",
        stage_name: "build",
        event: "fails"
      })

      # Should match
      count = ExGoCD.Notifications.dispatch("demo", "build", "fails", "Failed")
      assert count == 1

      # Should not match (wrong event)
      count2 = ExGoCD.Notifications.dispatch("demo", "build", "passes", "Passed")
      assert count2 == 0

      # Should not match (wrong stage)
      count3 = ExGoCD.Notifications.dispatch("demo", "test", "fails", "Failed")
      assert count3 == 0
    end

    test "matches All event filter for any event" do
      {:ok, user} =
        Accounts.create_user(%{username: "allnotify", display_name: "All Notify"})

      ExGoCD.Notifications.create_filter(%{
        user_id: user.id,
        pipeline_name: "demo",
        stage_name: "build",
        event: "all"
      })

      count = ExGoCD.Notifications.dispatch("demo", "build", "passes", "Passed")
      assert count == 1
    end
  end
end
