defmodule ExGoCDWeb.API.PersonalAccessTokenControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Repo
  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.{User, PersonalAccessToken}

  setup %{conn: conn} do
    # Clean up DB before each test
    Repo.delete_all(PersonalAccessToken)
    Repo.delete_all(User)

    conn = Plug.Test.init_test_session(conn, %{})

    {:ok, conn: conn}
  end

  describe "Personal Access Token CRUD APIs" do
    test "requires authentication for all token endpoints", %{conn: conn} do
      # GET index
      conn_idx = get(conn, ~p"/api/current_user/access_tokens")
      assert json_response(conn_idx, 401) == %{"error" => "Unauthorized"}

      # GET show
      conn_show = get(conn, ~p"/api/current_user/access_tokens/1")
      assert json_response(conn_show, 401) == %{"error" => "Unauthorized"}

      # POST create
      conn_create =
        post(conn, ~p"/api/current_user/access_tokens", %{"description" => "Test token"})

      assert json_response(conn_create, 401) == %{"error" => "Unauthorized"}

      # POST revoke
      conn_rev = post(conn, ~p"/api/current_user/access_tokens/1/revoke", %{})
      assert json_response(conn_rev, 401) == %{"error" => "Unauthorized"}
    end

    test "creates, lists, shows, and revokes tokens for authenticated user", %{conn: conn} do
      # 1. Create a user
      {:ok, user} =
        Accounts.create_user(%{
          username: "user_test",
          display_name: "User Test",
          roles: [],
          status: "Active"
        })

      conn = log_in_as(conn, user.username)

      # 2. POST create token
      conn_create =
        post(conn, ~p"/api/current_user/access_tokens", %{"description" => "Token for CLI"})

      assert token_resp = json_response(conn_create, 201)

      assert token_resp["id"] != nil
      assert token_resp["description"] == "Token for CLI"
      assert token_resp["username"] == "user_test"
      assert token_resp["revoked"] == false
      # Plain text token returned
      assert token_resp["token"] != nil
      _raw_token = token_resp["token"]
      token_id = token_resp["id"]

      # 3. GET index (list)
      conn_list = get(conn, ~p"/api/current_user/access_tokens")
      assert list_resp = json_response(conn_list, 200)
      assert length(list_resp) == 1
      [list_token] = list_resp
      assert list_token["id"] == token_id
      assert list_token["description"] == "Token for CLI"
      # No plain text token
      assert list_token["token"] == nil

      # 4. GET show (details)
      conn_show = get(conn, ~p"/api/current_user/access_tokens/#{token_id}")
      assert show_resp = json_response(conn_show, 200)
      assert show_resp["id"] == token_id
      assert show_resp["description"] == "Token for CLI"
      # No plain text token
      assert show_resp["token"] == nil

      # 5. POST revoke
      conn_rev =
        post(conn, ~p"/api/current_user/access_tokens/#{token_id}/revoke", %{
          "revoke_cause" => "token leak"
        })

      assert rev_resp = json_response(conn_rev, 200)
      assert rev_resp["id"] == token_id
      assert rev_resp["revoked"] == true
      assert rev_resp["revoked_by"] == user.username
      assert rev_resp["revoke_cause"] == "token leak"
      assert rev_resp["revoked_at"] != nil
    end

    test "does not let a user view or revoke another user's token", %{conn: conn} do
      {:ok, user1} =
        Accounts.create_user(%{username: "user1", display_name: "U1", status: "Active"})

      {:ok, user2} =
        Accounts.create_user(%{username: "user2", display_name: "U2", status: "Active"})

      # Create token for user1
      {:ok, token} = Accounts.create_user_token(user1.id, "User1 token")

      # Log in as user2
      conn = log_in_as(conn, user2.username)

      # Attempt to GET show user1's token -> 404 Not Found
      conn_show = get(conn, ~p"/api/current_user/access_tokens/#{token.id}")
      assert json_response(conn_show, 404) == %{"error" => "Token not found"}

      # Attempt to POST revoke user1's token -> 404 Not Found
      conn_rev = post(conn, ~p"/api/current_user/access_tokens/#{token.id}/revoke", %{})
      assert json_response(conn_rev, 404) == %{"error" => "Token not found"}
    end
  end

  describe "Bearer Token API Authentication" do
    test "authenticates requests with a valid Bearer token", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          username: "api_user",
          display_name: "API User",
          roles: ["admin"],
          status: "Active"
        })

      {:ok, token} = Accounts.create_user_token(user.id, "API token")

      # Access version endpoint without token
      conn_no_auth = get(conn, ~p"/api/version")
      # Public endpoint, works without auth
      assert json_response(conn_no_auth, 200)

      # Access protected endpoint /api/admin/environments (requires admin/developer/viewer permissions)
      # Let's activate security by configuring another admin user in the system
      {:ok, _} =
        Accounts.create_user(%{
          username: "system_admin",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      # No auth -> 403 Forbidden because they are guest viewer now
      conn_guest = get(conn, ~p"/api/admin/environments")
      assert json_response(conn_guest, 403) == %{"error" => "Forbidden"}

      # Valid Bearer token authentication -> 200 OK
      conn_auth =
        conn
        |> put_req_header("authorization", "Bearer #{token.token}")
        |> get(~p"/api/admin/environments")

      assert json_response(conn_auth, 200)

      # Last used at timestamp should be updated on token verify
      updated_token = Repo.get!(PersonalAccessToken, token.id)
      assert updated_token.last_used_at != nil
    end

    test "rejects requests with invalid or revoked Bearer token", %{conn: conn} do
      # Seed system admin to activate security mode
      {:ok, _} =
        Accounts.create_user(%{
          username: "sys_admin",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      {:ok, user} =
        Accounts.create_user(%{username: "user_revoked", display_name: "U", status: "Active"})

      {:ok, token} = Accounts.create_user_token(user.id, "Revoked token")
      {:ok, _} = Accounts.revoke_token(token, "sys_admin")

      # 1. Invalid token value
      conn_invalid =
        conn
        |> put_req_header("authorization", "Bearer non_existent_token")
        |> get(~p"/api/admin/environments")

      assert json_response(conn_invalid, 401) == %{"error" => "Invalid token"}

      # 2. Revoked token value
      conn_revoked =
        conn
        |> put_req_header("authorization", "Bearer #{token.token}")
        |> get(~p"/api/admin/environments")

      assert json_response(conn_revoked, 401) == %{"error" => "Invalid token"}
    end
  end
end
