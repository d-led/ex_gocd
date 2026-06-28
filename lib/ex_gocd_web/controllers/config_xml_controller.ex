defmodule ExGoCDWeb.ConfigXmlController do
  @moduledoc """
  Config XML export, import, and version revert at /admin/config_xml.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.ConfigVersion

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
        do_import(conn, xml)

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

  @doc "Revert to a previous config version by ID."
  def revert(conn, %{"version_id" => version_id}) do
    case Integer.parse(version_id) do
      {id, _} ->
        version = ConfigVersion.get!(id)
        xml = version.config_xml || config_json_to_xml(version.config_json)
        do_import(conn, xml)

      :error ->
        conn
        |> put_flash(:error, "Invalid version ID.")
        |> redirect(to: "/admin/config_xml")
    end
  end

  defp do_import(conn, xml) do
    case ExGoCD.ConfigXml.import_from_xml(xml) do
      {:ok, count} ->
        ExGoCD.ConfigSnapshot.after_mutation("admin", "config reverted from version")

        conn
        |> put_flash(:info, "Imported #{count} pipeline(s) successfully.")
        |> redirect(to: "/admin/config_xml")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Import failed: #{reason}")
        |> redirect(to: "/admin/config_xml")
    end
  end

  defp config_json_to_xml(_config_json) do
    ExGoCD.ConfigXml.generate()
  end
end
