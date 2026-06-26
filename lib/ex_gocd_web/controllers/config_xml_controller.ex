defmodule ExGoCDWeb.ConfigXmlController do
  @moduledoc """
  Config XML export and import at /admin/config_xml.
  """
  use ExGoCDWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end

  def show(conn, _params) do
    xml = ExGoCD.ConfigXml.generate()

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  def import_xml(conn, %{"file" => %{path: path, filename: _filename}}) do
    case File.read(path) do
      {:ok, xml} ->
        case ExGoCD.ConfigXml.import_from_xml(xml) do
          {:ok, count} ->
            conn
            |> put_flash(:info, "Imported #{count} pipeline(s) successfully.")
            |> redirect(to: "/admin/pipelines")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Import failed: #{reason}")
            |> redirect(to: "/admin/config_xml")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not read uploaded file: #{reason}")
        |> redirect(to: "/admin/config_xml")
    end
  end

  def import_xml(conn, _params) do
    conn
    |> put_flash(:error, "Please select a cruise-config.xml file to upload.")
    |> redirect(to: "/admin/config_xml")
  end
end
