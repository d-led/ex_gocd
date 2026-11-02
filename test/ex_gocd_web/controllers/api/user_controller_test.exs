defmodule ExGoCDWeb.API.UserControllerTest do
  @moduledoc """
  The users API changes who exists and what they may do, so it is admin-only:
  whoever can POST here can make themselves an admin. It was behind the plain
  `:api` pipeline, which authenticates a token and asks nothing else.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  setup do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, member} =
      Accounts.create_user(%{
        username: "member-#{System.unique_integer([:positive])}",
        display_name: "Member",
        roles: [],
        status: "Active"
      })

    %{admin: admin, member: member}
  end

  describe "as someone who is not an admin" do
    setup %{conn: conn, member: member} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> log_in_as(member.username)

      %{conn: conn}
    end

    test "cannot list users", %{conn: conn} do
      assert json_response(get(conn, "/api/users"), :forbidden)
    end

    test "cannot read a user", %{conn: conn, admin: admin} do
      assert json_response(get(conn, "/api/users/#{admin.username}"), :forbidden)
    end

    test "cannot create a user, and so cannot create an admin", %{conn: conn} do
      conn =
        post(conn, "/api/users", %{"username" => "sneaky", "roles" => ["admin"]})

      assert json_response(conn, :forbidden)
      assert Accounts.get_user_by_username("sneaky") == nil
    end

    test "cannot change a user", %{conn: conn, admin: admin} do
      assert json_response(
               patch(conn, "/api/users/#{admin.username}", %{"roles" => []}),
               :forbidden
             )
    end

    test "cannot delete a user", %{conn: conn, admin: admin} do
      assert json_response(delete(conn, "/api/users/#{admin.username}"), :forbidden)
      assert Accounts.get_user_by_username(admin.username)
    end
  end

  describe "as an admin" do
    setup %{conn: conn, admin: admin} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> log_in_as(admin.username)

      %{conn: conn}
    end

    test "lists the users it holds", %{conn: conn, admin: admin, member: member} do
      body = conn |> get("/api/users") |> json_response(200)

      usernames = Enum.map(body["users"], & &1["username"])
      assert admin.username in usernames
      assert member.username in usernames
    end

    test "reads one user", %{conn: conn, member: member} do
      body = conn |> get("/api/users/#{member.username}") |> json_response(200)

      assert body["username"] == member.username
      assert body["display_name"] == "Member"
    end

    test "says a user it does not have is missing", %{conn: conn} do
      body = conn |> get("/api/users/nobody-at-all") |> json_response(404)

      assert body["message"] =~ "nobody-at-all"
    end

    test "creates a user", %{conn: conn} do
      body =
        conn
        |> post("/api/users", %{"username" => "newcomer", "display_name" => "New Comer"})
        |> json_response(201)

      assert body["username"] == "newcomer"
      assert body["display_name"] == "New Comer"
      assert Accounts.get_user_by_username("newcomer")
    end

    test "says why a user cannot be created", %{conn: conn, member: member} do
      body =
        conn
        |> post("/api/users", %{"username" => member.username})
        |> json_response(422)

      assert body["message"] == "Failed to create user."
      assert body["errors"]
    end

    test "changes a user", %{conn: conn, member: member} do
      body =
        conn
        |> patch("/api/users/#{member.username}", %{"display_name" => "Renamed"})
        |> json_response(200)

      assert body["display_name"] == "Renamed"
    end

    test "changes roles", %{conn: conn, member: member} do
      body =
        conn
        |> patch("/api/users/#{member.username}", %{"roles" => ["admin"]})
        |> json_response(200)

      assert body["roles"] == ["admin"]
    end

    test "deletes a user", %{conn: conn, member: member} do
      body = conn |> delete("/api/users/#{member.username}") |> json_response(200)

      assert body["message"] =~ member.username
      assert Accounts.get_user_by_username(member.username) == nil
    end
  end
end
