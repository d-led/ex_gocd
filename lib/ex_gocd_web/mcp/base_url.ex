defmodule ExGoCDWeb.Mcp.BaseUrl do
  @moduledoc """
  The address a request arrived on, as a URL with no trailing path.

  Every link and every discovery document this server emits is built from this,
  not from configuration: a server reached on `localhost:4000` must answer with
  `localhost:4000`, and one reached through a proxy must answer with the name the
  proxy used. The default ports are the ones a browser leaves out.
  """

  @spec url(Plug.Conn.t()) :: String.t()
  def url(conn) do
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    "#{conn.scheme}://#{conn.host}#{port}"
  end
end
