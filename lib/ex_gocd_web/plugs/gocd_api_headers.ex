defmodule ExGoCDWeb.Plugs.GoCDAPIHeaders do
  @moduledoc """
  Sets GoCD API response headers per api.go.cd spec.

  - Content-Type: application/vnd.go.cd.v1+json; charset=utf-8
  Accepts both application/vnd.go.cd.v1+json and application/vnd.go.cd+json.
  """
  import Plug.Conn

  @gocd_content_type "application/vnd.go.cd.v1+json; charset=utf-8"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("content-type", @gocd_content_type)
  end
end
