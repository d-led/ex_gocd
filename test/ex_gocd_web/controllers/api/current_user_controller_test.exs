# Copyright 2026 ex_gocd
# Tests for GoCD Current User API.

defmodule ExGoCDWeb.API.CurrentUserControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{
        username: "current-user-#{System.unique_integer([:positive])}",
        display_name: "Jane Doe",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, user.username), user: user}
  end

  describe "GET /api/current_user" do
    test "answers with the user who is asking", %{conn: conn, user: user} do
      conn = get(conn, ~p"/api/current_user")

      assert %{
               "login_name" => login_name,
               "display_name" => "Jane Doe",
               "enabled" => true,
               "checkin_aliases" => []
             } = json_response(conn, 200)

      assert login_name == user.username
    end

    test "points at the user's own resource", %{conn: conn, user: user} do
      conn = get(conn, ~p"/go/api/current_user")

      assert %{"_links" => %{"self" => %{"href" => href}}} = json_response(conn, 200)
      assert href == "/api/users/#{user.username}"
    end

    test "refuses an unauthenticated caller" do
      conn = build_conn() |> get(~p"/api/current_user")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end
end
