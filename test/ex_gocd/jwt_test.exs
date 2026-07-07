defmodule ExGoCD.JWTTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.{Accounts, JWT}

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        username: "jwt-test-#{System.unique_integer([:positive])}",
        display_name: "JWT Test User",
        roles: ["admin", "developer"],
        status: "Active"
      })

    {:ok, user: user}
  end

  describe "generate/1" do
    test "returns a signed JWT token and jti", %{user: user} do
      assert {:ok, token, jti} = JWT.generate(user)

      assert is_binary(token)
      assert String.length(token) > 20
      assert is_binary(jti)
      assert String.length(jti) > 0
    end
  end

  describe "verify/1" do
    test "verifies a valid token and returns claims", %{user: user} do
      {:ok, token, _jti} = JWT.generate(user)
      assert {:ok, claims} = JWT.verify(token)

      assert claims["sub"] == to_string(user.id)
      assert claims["username"] == user.username
      assert claims["roles"] == ["admin", "developer"]
      assert is_integer(claims["iat"])
      assert is_binary(claims["jti"])
    end

    test "returns error for an invalid token" do
      assert {:error, _reason} = JWT.verify("not.a.valid.jwt")
    end

    test "returns error for a token signed with different secret" do
      other_key = :crypto.hash(:sha256, "different-secret-key-12345")
      other_signer = Joken.Signer.create("HS256", other_key)
      {:ok, token, _claims} = Joken.encode_and_sign(%{"sub" => "1"}, other_signer)

      assert {:error, _reason} = JWT.verify(token)
    end
  end

  describe "Accounts.create_user_token/2 (JWT-backed)" do
    test "creates a token that can be verified", %{user: user} do
      {:ok, token_record} = Accounts.create_user_token(user.id, "test-token")

      assert token_record.token != nil
      assert String.length(token_record.token) > 20
      assert token_record.description == "test-token"
      assert token_record.revoked == false

      # The returned token should be verifiable
      assert {:ok, claims} = JWT.verify(token_record.token)
      assert claims["sub"] == to_string(user.id)
      assert claims["username"] == user.username
    end
  end

  describe "Accounts.verify_access_token/1 (JWT-backed)" do
    test "returns user for a valid token", %{user: user} do
      {:ok, token_record} = Accounts.create_user_token(user.id, "api-token")
      assert {:ok, verified_user} = Accounts.verify_access_token(token_record.token)
      assert verified_user.username == user.username
      assert verified_user.id == user.id
    end

    test "returns error for invalid token" do
      assert {:error, :invalid_token} = Accounts.verify_access_token("garbage-token")
    end

    test "returns error for revoked token", %{user: user} do
      {:ok, token_record} = Accounts.create_user_token(user.id, "revocable-token")
      {:ok, _} = Accounts.revoke_token(token_record, "admin", "no longer needed")

      assert {:error, _reason} = Accounts.verify_access_token(token_record.token)
    end
  end
end
