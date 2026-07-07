defmodule ExGoCDWeb.API.Admin.EncryptionControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.{Accounts, Crypto, Repo}
  alias ExGoCD.Accounts.{PersonalAccessToken, User}

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "admin-enc-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> log_in_as(admin.username)

    {:ok, conn: conn}
  end

  describe "POST /api/admin/encrypt" do
    test "encrypts a plain text value and returns encrypted_value", %{conn: conn} do
      conn = post(conn, "/api/admin/encrypt", %{"value" => "my-secret-password"})

      assert json = json_response(conn, 200)
      assert %{"encrypted_value" => encrypted} = json
      assert String.starts_with?(encrypted, "AES:")
      assert {:ok, "my-secret-password"} = Crypto.decrypt(encrypted)
    end

    test "returns 400 when value parameter is missing", %{conn: conn} do
      conn = post(conn, "/api/admin/encrypt", %{})

      assert conn.status == 400
      assert %{"error" => msg} = json_response(conn, 400)
      assert msg =~ "Missing"
    end

    test "returns 400 when value is empty string", %{conn: conn} do
      conn = post(conn, "/api/admin/encrypt", %{"value" => ""})

      assert conn.status == 400
      assert %{"error" => msg} = json_response(conn, 400)
      assert msg =~ "empty"
    end

    test "each encryption produces a different ciphertext (random IV)", %{conn: conn} do
      e1 =
        conn
        |> post("/api/admin/encrypt", %{"value" => "same-password"})
        |> json_response(200)
        |> Map.get("encrypted_value")

      e2 =
        conn
        |> post("/api/admin/encrypt", %{"value" => "same-password"})
        |> json_response(200)
        |> Map.get("encrypted_value")

      assert e1 != e2
      assert {:ok, "same-password"} = Crypto.decrypt(e1)
      assert {:ok, "same-password"} = Crypto.decrypt(e2)
    end
  end
end
