defmodule ExGoCD.Mcp.OAuthTest do
  @moduledoc """
  The parts of the authorization round trip that are about the code itself: who
  may register, and what a code is bound to.
  """

  use ExGoCD.DataCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.Mcp.{OAuth, OAuthClient, OAuthCode}

  @redirect_uri "http://127.0.0.1:9999/callback"

  # One verifier for the whole file: a challenge and the exchange that trades it
  # have to agree, and nothing here is about the value's freshness.
  @verifier "verifier-" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        username: "reader",
        display_name: "Reader",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, client} =
      OAuth.register_client(%{"client_name" => "Test", "redirect_uris" => [@redirect_uri]})

    {:ok, user: user, client: client}
  end

  describe "register_client/1" do
    test "refuses a redirect that is not an absolute http(s) URI" do
      assert {:error, message} =
               OAuth.register_client(%{"redirect_uris" => ["ftp://example.test/cb"]})

      assert message =~ "http(s)"
    end

    test "refuses a registration without a redirect at all" do
      assert {:error, message} = OAuth.register_client(%{})
      assert message =~ "non-empty list"
    end

    test "a registration is a public client with an unguessable id", %{client: client} do
      assert String.starts_with?(client.client_id, "gocd_")
      assert OAuthClient.allows_redirect?(client, @redirect_uri)
      refute OAuthClient.allows_redirect?(client, "http://other.example/cb")
    end
  end

  describe "a code" do
    test "is only kept as a hash", %{client: client, user: user} do
      assert {:ok, code} = OAuth.issue_code(client, user, @redirect_uri, challenge(), "mcp")

      refute Repo.get_by(OAuthCode, code_hash: code)
      assert Repo.get_by(OAuthCode, code_hash: hash(code))
    end

    test "expires, and says so rather than pretending the code was wrong", %{
      client: client,
      user: user
    } do
      {:ok, code} = OAuth.issue_code(client, user, @redirect_uri, challenge(), "mcp")
      expire(code)

      assert OAuth.exchange(client, @redirect_uri, code, @verifier) == {:error, :expired}
    end

    test "belongs to the client and redirect it was issued for", %{client: client, user: user} do
      {:ok, code} = OAuth.issue_code(client, user, @redirect_uri, challenge(), "mcp")
      {:ok, other} = OAuth.register_client(%{"redirect_uris" => ["http://127.0.0.1:9998/cb"]})

      assert OAuth.exchange(other, @redirect_uri, code, @verifier) == {:error, :client_mismatch}

      assert OAuth.exchange(client, "http://127.0.0.1:9998/cb", code, @verifier) ==
               {:error, :redirect_mismatch}
    end

    test "is traded for a token that identifies the reader who approved it", %{
      client: client,
      user: user
    } do
      {:ok, code} = OAuth.issue_code(client, user, @redirect_uri, challenge(), "mcp")

      assert {:ok, %{user: approved}} = OAuth.exchange(client, @redirect_uri, code, @verifier)
      assert approved.username == "reader"

      assert {:ok, token} = OAuth.mint_access_token(client, user)
      assert {:ok, %{username: "reader"}} = Accounts.verify_access_token(token)
    end
  end

  defp challenge, do: Base.url_encode64(:crypto.hash(:sha256, @verifier), padding: false)

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp expire(code) do
    Repo.get_by!(OAuthCode, code_hash: hash(code))
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()
  end
end
