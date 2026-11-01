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
        {_outcome, conn} = apply_xml(conn, xml)
        conn

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
      {id, _} -> revert_to(conn, ConfigVersion.get!(id))
      :error -> redirect_with_error(conn, "Invalid version ID.")
    end
  end

  # A revert restores the XML as it was recorded, and then the sections the XML
  # cannot express from the same version's JSON: artifact stores, secret configs,
  # package repositories and config repos live only in the JSON. Regenerating the
  # XML from the current config would look like a revert and change nothing, so a
  # version without stored XML is refused instead.
  defp revert_to(conn, %ConfigVersion{config_xml: xml} = version)
       when is_binary(xml) and xml != "" do
    case apply_xml(conn, xml) do
      {:ok, conn} ->
        ExGoCD.ConfigRestore.restore(version.config_json || %{})
        conn

      {:error, conn} ->
        conn
    end
  end

  defp revert_to(conn, %ConfigVersion{id: id}) do
    redirect_with_error(conn, "Version #{id} has no stored XML to revert to.")
  end

  defp redirect_with_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: "/admin/config_xml")
  end

  defp apply_xml(conn, xml) do
    case ExGoCD.ConfigXml.import_from_xml(xml) do
      {:ok, %{pipelines: p_count, elastic_profiles: e_count}} ->
        ExGoCD.ConfigSnapshot.after_mutation("admin", "config imported")

        msg = "Imported #{p_count} pipeline(s), #{e_count} elastic profile(s)."

        {:ok,
         conn
         |> put_flash(:info, msg)
         |> redirect(to: "/admin/config_xml")}

      {:error, reason} ->
        {:error,
         conn
         |> put_flash(:error, "Import failed: #{reason}")
         |> redirect(to: "/admin/config_xml")}
    end
  end
end
