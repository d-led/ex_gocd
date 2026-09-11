defmodule ExGoCDWeb.API.Admin.ConfigXmlController do
  @moduledoc """
  Config XML export as an API. GoCD parity: GET /go/api/admin/config.xml.
  """
  use ExGoCDWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, ExGoCD.ConfigXml.generate())
  end
end
