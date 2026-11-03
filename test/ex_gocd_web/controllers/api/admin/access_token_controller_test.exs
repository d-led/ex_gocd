# Copyright 2026 ex_gocd
# Tests for GoCD admin access-token API.

defmodule ExGoCDWeb.API.Admin.AccessTokenControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  setup %{conn: conn} do
    {:ok, admin} = create_user("admin")
    {:ok, owner} = create_user("owner")

    {:ok, active} = Accounts.create_user_token(owner.id, "still in use")
    {:ok, revoked} = Accounts.create_user_token(owner.id, "no longer wanted")
    {:ok, _} = Accounts.revoke_token(revoked, owner.username, "rotated")

    %{
      conn: log_in_as(conn, admin.username),
      admin: admin,
      owner: owner,
      active: active,
      revoked: revoked
    }
  end

  describe "GET /api/admin/access_tokens" do
    test "lists every user's tokens, revoked ones included", %{
      conn: conn,
      owner: owner,
      active: active,
      revoked: revoked
    } do
      conn = get(conn, ~p"/api/admin/access_tokens")

      assert %{"_embedded" => %{"access_tokens" => tokens}} = json_response(conn, 200)
      assert Enum.all?(tokens, &(&1["username"] == owner.username))

      assert %{"revoked" => false} = Enum.find(tokens, &(&1["id"] == active.id))

      assert %{"revoked" => true, "revoke_cause" => "rotated"} =
               Enum.find(tokens, &(&1["id"] == revoked.id))
    end

    test "filter=active leaves the revoked ones out", %{
      conn: conn,
      active: active,
      revoked: revoked
    } do
      conn = get(conn, ~p"/api/admin/access_tokens?filter=active")

      assert %{"_embedded" => %{"access_tokens" => [only]}} = json_response(conn, 200)
      assert only["id"] == active.id
      refute only["id"] == revoked.id
    end

    test "filter=revoked shows only what was revoked", %{conn: conn, revoked: revoked} do
      conn = get(conn, ~p"/api/admin/access_tokens?filter=revoked")

      assert %{"_embedded" => %{"access_tokens" => [only]}} = json_response(conn, 200)
      assert only["id"] == revoked.id
    end
  end

  describe "GET /api/admin/access_tokens/:id" do
    test "describes one token of another user", %{conn: conn, active: active} do
      conn = get(conn, ~p"/api/admin/access_tokens/#{active.id}")

      assert %{"id" => id, "description" => "still in use"} = json_response(conn, 200)
      assert id == active.id
    end

    test "answers not found for an id that does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/admin/access_tokens/0")

      assert %{"message" => message} = json_response(conn, :not_found)
      assert message =~ "0"
    end
  end

  describe "POST /api/admin/access_tokens/:id/revoke" do
    test "revokes someone else's token and names the admin who did it", %{
      conn: conn,
      admin: admin,
      active: active
    } do
      conn = post(conn, ~p"/go/api/admin/access_tokens/#{active.id}/revoke")

      assert %{"revoked" => true, "revoked_by" => revoked_by} = json_response(conn, 200)
      assert revoked_by == admin.username
      assert Accounts.get_token(active.id).revoked
    end
  end

  defp create_user(username) do
    Accounts.create_user(%{
      username: "#{username}-#{System.unique_integer([:positive])}",
      display_name: username,
      roles: [if(username == "admin", do: "admin", else: "viewer")],
      status: "Active"
    })
  end
end
