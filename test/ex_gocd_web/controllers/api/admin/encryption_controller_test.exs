defmodule ExGoCDWeb.API.Admin.EncryptionControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.{Repo, Accounts, Crypto}
  alias ExGoCD.Accounts.{User, PersonalAccessToken}

  setup %{conn: conn} do
    Repo.delete_all(PersonalAccessToken)
    Repo.delete_all(User)
    {:ok, conn: conn}
  end

  describe "POST /api/admin/encrypt" do
    test "encrypts a plain text value and returns encrypted_value", %{conn: conn} do
      conn = conn |> auth() |> post("/api/admin/encrypt", %{"value" => "my-secret-password"})

      assert json = json_response(conn, 200)
      assert %{"encrypted_value" => encrypted} = json
      assert String.starts_with?(encrypted, "AES:")
      assert {:ok, "my-secret-password"} = Crypto.decrypt(encrypted)
    end

    test "returns 400 when value parameter is missing", %{conn: conn} do
      conn = conn |> auth() |> post("/api/admin/encrypt", %{})

      assert conn.status == 400
      assert %{"error" => msg} = json_response(conn, 400)
      assert msg =~ "Missing"
    end

    test "returns 400 when value is empty string", %{conn: conn} do
      conn = conn |> auth() |> post("/api/admin/encrypt", %{"value" => ""})

      assert conn.status == 400
      assert %{"error" => msg} = json_response(conn, 400)
      assert msg =~ "empty"
    end

    test "each encryption produces a different ciphertext (random IV)", %{conn: conn} do
      e1 =
        conn
        |> auth()
        |> post("/api/admin/encrypt", %{"value" => "same-password"})
        |> json_response(200)
        |> Map.get("encrypted_value")

      e2 =
        conn
        |> auth()
        |> post("/api/admin/encrypt", %{"value" => "same-password"})
        |> json_response(200)
        |> Map.get("encrypted_value")

      assert e1 != e2
      assert {:ok, "same-password"} = Crypto.decrypt(e1)
      assert {:ok, "same-password"} = Crypto.decrypt(e2)
    end
  end

  defp auth(conn) do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, token} = Accounts.create_user_token(admin.id, "test")

    conn |> Plug.Conn.put_req_header("authorization", "bearer #{token.token}")
  end
end
