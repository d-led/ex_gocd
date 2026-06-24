defmodule ExGoCDWeb.ConfigXmlController do
  @moduledoc """
  Serves the cruise-config.xml export at /admin/config_xml.
  """
  use ExGoCDWeb, :controller

  def show(conn, _params) do
    xml = ExGoCD.ConfigXml.generate()

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end
end
