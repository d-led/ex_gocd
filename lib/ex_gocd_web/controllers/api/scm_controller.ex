defmodule ExGoCDWeb.API.SCMController do
  @moduledoc """
  API controller for SCM materials (B27).

  GET /api/admin/scms — lists all SCM materials across pipelines.
  GET /api/admin/scms/:id — shows a specific SCM material.
  """

  use ExGoCDWeb, :controller

  alias ExGoCD.Pipelines

  @doc "GET /api/admin/scms"
  def index(conn, _params) do
    pipelines = Pipelines.list_pipelines()

    materials =
      pipelines
      |> Enum.flat_map(& &1.materials)
      |> Enum.uniq_by(&{&1.type, &1.url})
      |> Enum.map(&material_map(&1, pipelines))

    json(conn, %{materials: materials})
  end

  @doc "GET /api/admin/scms/:id"
  def show(conn, %{"id" => id}) do
    pipelines = Pipelines.list_pipelines()

    materials =
      pipelines
      |> Enum.flat_map(& &1.materials)
      |> Enum.uniq_by(&{&1.type, &1.url})

    case Enum.at(materials, String.to_integer(id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "SCM not found"})

      mat ->
        json(conn, material_map(mat, pipelines))
    end
  end

  defp material_map(mat, pipelines) do
    %{
      id: mat.id,
      type: mat.type || "git",
      url: mat.url,
      branch: mat.branch || "main",
      username: mat.username,
      auto_update: mat.auto_update,
      destination: mat.destination,
      pipelines: pipeline_refs(mat, pipelines)
    }
  end

  defp pipeline_refs(mat, pipelines) do
    pipelines
    |> Enum.filter(fn p ->
      Enum.any?(p.materials, &(&1.url == mat.url))
    end)
    |> Enum.map(&%{name: &1.name, group: &1.pipeline_group})
  end
end
