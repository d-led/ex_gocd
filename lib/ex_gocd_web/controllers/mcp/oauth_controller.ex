defmodule ExGoCDWeb.Mcp.OAuthController do
  @moduledoc """
  The three machine-readable steps of the MCP authorization round trip, and the
  one page a person sees.

    * `GET /.well-known/oauth-protected-resource` (RFC 9728) — which resource a
      token is for and which authorization server issues it;
    * `GET /.well-known/oauth-authorization-server` (RFC 8414) — what this
      server can do: public clients, authorization code, PKCE S256;
    * `POST /oauth/register` — self-registration, no secret;
    * `GET`/`POST /oauth/authorize` — the browser step: the reader signs in (or
      arrives signed in through `oauth2-proxy`) and approves the client;
    * `POST /oauth/token` — the code, exchanged for a GoCD access token.

  An authorization request is validated *before* anything is redirected: an
  unknown client or an unregistered `redirect_uri` is answered with a `400` in
  the browser, never with a redirect carrying a code to a URL the client did not
  declare.
  """

  use ExGoCDWeb, :controller

  alias ExGoCD.Mcp.{Identity, OAuth, OAuthClient}
  alias ExGoCDWeb.Mcp.BaseUrl

  @doc "GET /.well-known/oauth-protected-resource"
  def protected_resource(conn, _params) do
    base = BaseUrl.url(conn)

    json(conn, %{
      "resource" => base <> "/mcp",
      "authorization_servers" => [base],
      "bearer_methods_supported" => ["header"],
      "scopes_supported" => OAuth.scopes()
    })
  end

  @doc "GET /.well-known/oauth-authorization-server"
  def authorization_server(conn, _params) do
    base = BaseUrl.url(conn)

    json(conn, %{
      "issuer" => base,
      "authorization_endpoint" => base <> "/oauth/authorize",
      "token_endpoint" => base <> "/oauth/token",
      "registration_endpoint" => base <> "/oauth/register",
      "response_types_supported" => ["code"],
      "grant_types_supported" => ["authorization_code"],
      "token_endpoint_auth_methods_supported" => ["none"],
      "code_challenge_methods_supported" => ["S256"],
      "scopes_supported" => OAuth.scopes()
    })
  end

  @doc "POST /oauth/register — RFC 7591, public clients only."
  def register(conn, params) do
    case OAuth.register_client(params) do
      {:ok, client} ->
        conn
        |> put_status(:created)
        |> json(%{
          "client_id" => client.client_id,
          "client_id_issued_at" => DateTime.to_unix(client.inserted_at),
          "client_name" => client.client_name,
          "redirect_uris" => client.redirect_uris,
          "token_endpoint_auth_method" => "none",
          "grant_types" => ["authorization_code"],
          "response_types" => ["code"]
        })

      {:error, message} when is_binary(message) ->
        oauth_error(conn, 400, "invalid_redirect_uri", message)

      {:error, %Ecto.Changeset{}} ->
        oauth_error(conn, 400, "invalid_client_metadata", "The registration is incomplete.")
    end
  end

  @doc "GET /oauth/authorize — validate the request, then ask the reader."
  def authorize(conn, params) do
    with {:ok, request} <- authorization_request(params) do
      case Identity.session_user(conn) do
        nil -> conn |> redirect(to: "/auth/login?return_to=" <> URI.encode_www_form(here(conn)))
        user -> render_consent(conn, request, user)
      end
    else
      {:error, description} -> oauth_error(conn, 400, "invalid_request", description)
    end
  end

  @doc "POST /oauth/authorize — the reader's decision, approved or denied."
  def approve(conn, params) do
    with {:ok, request} <- authorization_request(params) do
      case Identity.session_user(conn) do
        nil ->
          oauth_error(
            conn,
            401,
            "access_denied",
            "The approval must come from a signed-in browser."
          )

        user ->
          decide(conn, request, user, params["decision"])
      end
    else
      {:error, description} -> oauth_error(conn, 400, "invalid_request", description)
    end
  end

  @doc "POST /oauth/token — trade a code for a GoCD access token."
  def token(conn, params) do
    with {:ok, client} <- token_client(params),
         {:ok, redirect_uri} <- required(params, "redirect_uri"),
         {:ok, code} <- required(params, "code") do
      case OAuth.exchange(client, redirect_uri, code, params["code_verifier"]) do
        {:ok, %{user: user, client: client}} -> issue_token(conn, client, user)
        {:error, reason} -> oauth_error(conn, 400, "invalid_grant", exchange_message(reason))
      end
    else
      {:error, description} -> oauth_error(conn, 400, "invalid_request", description)
    end
  end

  # ── the flow ───────────────────────────────────────────────────────

  defp render_consent(conn, request, user) do
    render(conn, :authorize,
      layout: false,
      request: request,
      user: user,
      csrf_token: get_csrf_token()
    )
  end

  defp decide(conn, request, user, "approve") do
    case OAuth.issue_code(
           request.client,
           user,
           request.redirect_uri,
           request.code_challenge,
           request.scope
         ) do
      {:ok, code} ->
        redirect_with(conn, request.redirect_uri, %{"code" => code, "state" => request.state})

      {:error, _changeset} ->
        oauth_error(conn, 500, "server_error", "The authorization code could not be issued.")
    end
  end

  defp decide(conn, request, _user, _denied) do
    redirect_with(conn, request.redirect_uri, %{
      "error" => "access_denied",
      "error_description" => "The reader declined this client.",
      "state" => request.state
    })
  end

  defp issue_token(conn, client, user) do
    case OAuth.mint_access_token(client, user) do
      {:ok, token} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{
          "access_token" => token,
          "token_type" => "Bearer",
          "scope" => Enum.join(OAuth.scopes(), " ")
        })

      {:error, _reason} ->
        oauth_error(conn, 500, "server_error", "An access token could not be minted.")
    end
  end

  # ── validating the request ─────────────────────────────────────────

  defp authorization_request(params) do
    with {:ok, client_id} <- required(params, "client_id"),
         {:ok, client} <- registered_client(client_id),
         {:ok, redirect_uri} <- allowed_redirect(client, params),
         {:ok, challenge} <- code_challenge(params) do
      {:ok,
       %{
         client: client,
         redirect_uri: redirect_uri,
         code_challenge: challenge,
         scope: params["scope"],
         state: params["state"]
       }}
    end
  end

  defp token_client(params) do
    with {:ok, :authorization_code} <- grant_type(params),
         {:ok, client_id} <- required(params, "client_id"),
         {:ok, client} <- registered_client(client_id) do
      {:ok, client}
    end
  end

  defp grant_type(%{"grant_type" => "authorization_code"}), do: {:ok, :authorization_code}

  defp grant_type(_params),
    do: {:error, "Only `grant_type=authorization_code` is supported."}

  defp registered_client(client_id) do
    case OAuth.get_client(client_id) do
      nil -> {:error, "The client is not registered here."}
      client -> {:ok, client}
    end
  end

  defp allowed_redirect(%OAuthClient{} = client, params) do
    with {:ok, redirect_uri} <- required(params, "redirect_uri") do
      if OAuthClient.allows_redirect?(client, redirect_uri) do
        {:ok, redirect_uri}
      else
        {:error, "`redirect_uri` is not one this client registered."}
      end
    end
  end

  defp code_challenge(params) do
    with {:ok, _code} <- response_type(params),
         {:ok, challenge} <- required(params, "code_challenge"),
         {:ok, _method} <- challenge_method(params) do
      {:ok, challenge}
    end
  end

  defp response_type(%{"response_type" => "code"}), do: {:ok, "code"}
  defp response_type(%{"response_type" => nil}), do: {:ok, "code"}
  defp response_type(_params), do: {:error, "Only `response_type=code` is supported."}

  defp challenge_method(%{"code_challenge_method" => "S256"}), do: {:ok, "S256"}
  defp challenge_method(%{"code_challenge_method" => nil}), do: {:ok, "S256"}
  defp challenge_method(_params), do: {:error, "`code_challenge_method` must be S256."}

  defp required(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, "`#{key}` is required."}
    end
  end

  # ── responses ──────────────────────────────────────────────────────

  defp redirect_with(conn, redirect_uri, params) do
    uri = URI.parse(redirect_uri)
    query = URI.decode_query(uri.query || "")
    query = Enum.reduce(params, query, fn {key, value}, acc -> put_if(acc, key, value) end)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> redirect(external: URI.to_string(%{uri | query: URI.encode_query(query)}))
  end

  defp put_if(query, _key, nil), do: query
  defp put_if(query, key, value), do: Map.put(query, key, value)

  defp oauth_error(conn, status, error, description) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(
      status,
      Jason.encode!(%{"error" => error, "error_description" => description})
    )
  end

  defp exchange_message(:unknown_code), do: "The code is not one this server issued."
  defp exchange_message(:client_mismatch), do: "The code was issued to another client."
  defp exchange_message(:redirect_mismatch), do: "The code was issued for another redirect URI."
  defp exchange_message(:expired), do: "The code has expired; start the authorization again."
  defp exchange_message(:bad_verifier), do: "The code verifier does not match the code challenge."
  defp exchange_message(:already_used), do: "The code has already been exchanged."

  defp here(conn) do
    case conn.query_string do
      "" -> conn.request_path
      query -> conn.request_path <> "?" <> query
    end
  end
end
