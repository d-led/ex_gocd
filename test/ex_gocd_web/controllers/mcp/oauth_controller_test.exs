defmodule ExGoCDWeb.Mcp.OAuthControllerTest do
  @moduledoc """
  The authorization round trip as a client walks it: discovery, registration,
  consent, and a code traded for a token that the MCP endpoint accepts.
  """

  use ExGoCDWeb.ConnCase, async: false

  alias ExGoCD.Accounts
  alias ExGoCD.Mcp.Tools

  @redirect_uri "http://127.0.0.1:9999/callback"

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{
        username: "mcp-reader",
        display_name: "MCP Reader",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, conn: log_in_as(conn, user.username), user: user}
  end

  describe "discovery" do
    test "the protected-resource document names the resource and where to get a token", %{
      conn: conn
    } do
      body = conn |> get("/.well-known/oauth-protected-resource") |> json_response(200)

      assert String.ends_with?(body["resource"], "/mcp")
      assert [server] = body["authorization_servers"]
      assert server == "http://www.example.com"
      assert body["bearer_methods_supported"] == ["header"]
    end

    test "the form a client derives from the resource URL is served too", %{conn: conn} do
      assert conn |> get("/.well-known/oauth-protected-resource/mcp") |> json_response(200)
    end

    test "the authorization-server document says what this server can do", %{conn: conn} do
      body = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

      assert body["issuer"] == "http://www.example.com"
      assert body["code_challenge_methods_supported"] == ["S256"]
      assert body["token_endpoint_auth_methods_supported"] == ["none"]
      assert String.ends_with?(body["registration_endpoint"], "/oauth/register")
    end
  end

  describe "registration" do
    test "a public client registers itself and is told its id", %{conn: conn} do
      body = register(conn)

      assert String.starts_with?(body["client_id"], "gocd_")
      assert body["redirect_uris"] == [@redirect_uri]
      assert body["token_endpoint_auth_method"] == "none"
    end

    test "a redirect that is not an absolute URI is refused", %{conn: conn} do
      body =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/oauth/register", %{"redirect_uris" => ["/not/absolute"]})
        |> json_response(400)

      assert body["error"] == "invalid_redirect_uri"
    end
  end

  describe "the round trip" do
    test "a registered client is approved and its token works on /mcp", %{conn: conn} do
      client = register(conn)
      verifier = verifier()
      challenge = challenge(verifier)

      consent =
        conn
        |> get("/oauth/authorize", authorize_params(client, challenge))
        |> html_response(200)

      assert consent =~ "Test client"
      assert consent =~ "name=\"_csrf_token\""

      redirect =
        conn
        |> skip_csrf()
        |> post(
          "/oauth/authorize",
          Map.put(authorize_params(client, challenge), "decision", "approve")
        )
        |> redirected_to()

      code = code_from(redirect)

      token_body =
        build_conn()
        |> post("/oauth/token", %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect_uri,
          "code" => code,
          "code_verifier" => verifier
        })
        |> json_response(200)

      assert token_body["token_type"] == "Bearer"

      body =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> token_body["access_token"])
        |> put_req_header("content-type", "application/json")
        |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
        |> json_response(200)

      assert length(body["result"]["tools"]) == Tools.count()
    end

    test "a code is refused to a verifier that does not match it", %{conn: conn} do
      client = register(conn)
      verifier = verifier()

      code = approve(conn, client, challenge(verifier))

      body =
        build_conn()
        |> post("/oauth/token", %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect_uri,
          "code" => code,
          "code_verifier" => verifier()
        })
        |> json_response(400)

      assert body["error"] == "invalid_grant"
      assert body["error_description"] =~ "verifier"
    end

    test "a code cannot be traded twice", %{conn: conn} do
      client = register(conn)
      verifier = verifier()
      code = approve(conn, client, challenge(verifier))
      token_request = token_request(client, code, verifier)

      assert build_conn() |> post("/oauth/token", token_request) |> json_response(200)
      assert build_conn() |> post("/oauth/token", token_request) |> json_response(400)
    end

    test "an unregistered redirect is refused in the browser, never redirected to", %{conn: conn} do
      client = register(conn)

      body =
        conn
        |> get("/oauth/authorize", %{
          "response_type" => "code",
          "client_id" => client["client_id"],
          "redirect_uri" => "http://attacker.example/callback",
          "code_challenge" => challenge(verifier()),
          "code_challenge_method" => "S256"
        })
        |> json_response(400)

      assert body["error"] == "invalid_request"
    end

    test "a reader who is not signed in is sent to sign in and brought back", %{user: user} do
      client = register(build_conn())

      conn =
        build_conn()
        |> get("/oauth/authorize", authorize_params(client, challenge(verifier())))
        |> redirected_to()
        |> then(&get(build_conn(), &1))

      assert html_response(conn, 200) =~ "Sign In"
      assert conn.resp_body =~ "/oauth/authorize"

      conn =
        conn
        |> skip_csrf()
        |> post("/auth/login", %{
          "session" => %{"username" => user.username},
          "return_to" => "/oauth/authorize"
        })
        |> redirected_to()

      assert conn == "/oauth/authorize"
    end
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp register(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/oauth/register", %{
      "client_name" => "Test client",
      "redirect_uris" => [@redirect_uri]
    })
    |> json_response(201)
  end

  defp verifier,
    do: "verifier-" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp challenge(verifier), do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

  defp authorize_params(client, challenge) do
    %{
      "response_type" => "code",
      "client_id" => client["client_id"],
      "redirect_uri" => @redirect_uri,
      "code_challenge" => challenge,
      "code_challenge_method" => "S256",
      "state" => "state-123"
    }
  end

  defp approve(conn, client, challenge) do
    conn
    |> skip_csrf()
    |> post(
      "/oauth/authorize",
      Map.put(authorize_params(client, challenge), "decision", "approve")
    )
    |> redirected_to()
    |> code_from()
  end

  defp token_request(client, code, verifier) do
    %{
      "grant_type" => "authorization_code",
      "client_id" => client["client_id"],
      "redirect_uri" => @redirect_uri,
      "code" => code,
      "code_verifier" => verifier
    }
  end

  defp code_from(redirect) do
    assert redirect =~ "state=state-123"
    URI.parse(redirect).query |> URI.decode_query() |> Map.fetch!("code")
  end

  # The consent form carries the CSRF token a browser would send; a test posts
  # without it, which is the one thing the form's own token protects against.
  defp skip_csrf(conn), do: put_private(conn, :plug_skip_csrf_protection, true)
end
