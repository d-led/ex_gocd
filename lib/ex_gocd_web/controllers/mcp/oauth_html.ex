defmodule ExGoCDWeb.Mcp.OAuthHTML do
  @moduledoc """
  The one page the authorization round trip shows a person: consent.

  It is a standalone document rather than part of the application's layout —
  nobody browsing pipelines ends up here, and an MCP client opens it in whatever
  browser it can find.
  """

  use ExGoCDWeb, :html

  embed_templates "oauth_html/*"
end
