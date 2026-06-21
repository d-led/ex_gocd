defmodule ExGoCDWeb.Plugs.CacheBodyReader do
  @moduledoc """
  A custom body reader plug that reads and caches the raw request body on the connection assigns
  under `conn.assigns[:raw_body]`. This is required for verifying webhook signatures,
  as standard JSON/form parsers consume the request body.
  """
  import Plug.Conn

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        raw_body = (conn.assigns[:raw_body] || "") <> body
        conn = assign(conn, :raw_body, raw_body)
        {:ok, body, conn}

      {:more, body, conn} ->
        raw_body = (conn.assigns[:raw_body] || "") <> body
        conn = assign(conn, :raw_body, raw_body)
        {:more, body, conn}

      other ->
        other
    end
  end
end
