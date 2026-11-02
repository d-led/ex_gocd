defmodule ExGoCDWeb.Plugs.McpAuth do
  @moduledoc """
  Resolves the caller of an MCP request, or answers with the challenge the MCP
  authorization specification expects.

  Two answers only: a `401` that names where to get a credential, or an
  `assign` the tools can read. What counts as a credential — a bearer token, a
  basic pair, a session from the browser or from `oauth2-proxy`'s forwarded
  header, or nothing at all on a server that does not insist — is decided by
  `ExGoCD.Mcp.Identity`, so this plug and the rest of the server cannot drift
  apart.

  The challenge carries `resource_metadata` (RFC 9728): a client that supports
  remote MCP servers reads that document and starts the OAuth flow by itself,
  which is why the endpoint can be useful to such a client without anyone
  pasting a token.
  """

  import Plug.Conn

  alias ExGoCD.Mcp.Identity
  alias ExGoCDWeb.Mcp.BaseUrl

  def init(opts), do: opts

  def call(conn, _opts) do
    case Identity.identity(conn) do
      {:ok, user} -> assign(conn, :mcp_user, user)
      {:error, reason} -> challenge(conn, reason)
    end
  end

  defp challenge(conn, reason) do
    {error, message} = describe(reason)

    conn
    |> put_resp_header("www-authenticate", challenge_header(conn, reason))
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{"error" => error, "message" => message}))
    |> halt()
  end

  defp challenge_header(conn, reason) do
    metadata = BaseUrl.url(conn) <> "/.well-known/oauth-protected-resource"
    base = ~s(Bearer realm="gocd", resource_metadata="#{metadata}")

    case reason do
      :unauthorized ->
        base

      other ->
        base <> ~s(, error="invalid_token", error_description="#{error_description(other)}")
    end
  end

  defp error_description(:invalid_credentials), do: "The basic credentials were rejected"
  defp error_description(:account_disabled), do: "The account is disabled"

  defp error_description(_invalid_token),
    do: "The token is not one this server issued, or it was revoked"

  defp describe(:unauthorized) do
    {"unauthorized",
     "This MCP server requires a credential: a GoCD access token, basic authentication, " <>
       "or the OAuth flow described by the challenge's `resource_metadata` document."}
  end

  defp describe(:invalid_token) do
    {"invalid_token",
     "The bearer token was rejected: it is not one this server issued, or it was revoked."}
  end

  defp describe(:invalid_credentials) do
    {"invalid_credentials", "The basic credentials were rejected."}
  end

  defp describe(:account_disabled) do
    {"account_disabled", "This account is disabled."}
  end
end
