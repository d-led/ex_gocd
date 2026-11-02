defmodule ExGoCDWeb.API.SCMController do
  @moduledoc """
  API controller for SCM materials (B27).

  GET /api/admin/scms — lists all SCM materials across pipelines.
  GET /api/admin/scms/:id — shows a specific SCM material.

  A material is listed once per type and URL however many pipelines use it, and
  is answered by the id the database gave it.
  """

  use ExGoCDWeb, :controller

  alias ExGoCD.Pipelines

  @doc "GET /api/admin/scms"
  def index(conn, _params) do
    pipelines = Pipelines.list_pipelines()
    materials = pipelines |> Enum.flat_map(& &1.materials) |> Enum.uniq_by(&identity/1)

    json(conn, %{materials: Enum.map(materials, &material_map(&1, pipelines))})
  end

  @doc "GET /api/admin/scms/:id"
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- parse_counter(id),
         %{} = material <- Enum.find(materials(), &(&1.id == id)) do
      json(conn, material_map(material, Pipelines.list_pipelines()))
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "SCM not found"})
    end
  end

  defp materials do
    Pipelines.list_pipelines()
    |> Enum.flat_map(& &1.materials)
    |> Enum.uniq_by(&identity/1)
  end

  defp material_map(material, pipelines) do
    %{
      id: material.id,
      type: material.type || "git",
      url: material.url,
      branch: material.branch || "main",
      username: material.username,
      auto_update: material.auto_update,
      destination: material.destination,
      pipelines: pipeline_refs(material, pipelines)
    }
  end

  defp pipeline_refs(material, pipelines) do
    pipelines
    |> Enum.filter(fn pipeline ->
      Enum.any?(pipeline.materials, &(identity(&1) == identity(material)))
    end)
    |> Enum.map(&%{name: &1.name, group: &1.group})
  end

  defp identity(material), do: {material.type, material.url}
end
