defmodule ExGoCDWeb.API.MaterialsController do
  @moduledoc """
  GoCD Materials API (api-materials-v1): the materials this server has configured.

  This answers what a material *is* — the type and the attributes that tell it
  apart — not what it has fetched. A password is not part of it: GoCD hands out
  the encrypted form, and the material row keeps none.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.Material

  @doc "GET /api/config/materials"
  def index(conn, _params) do
    materials = Pipelines.list_materials()

    json(conn, %{
      _links: %{
        doc: %{href: "https://api.gocd.org/#materials"},
        self: %{href: "/api/config/materials"}
      },
      _embedded: %{materials: Enum.map(materials, &material_json/1)}
    })
  end

  defp material_json(%Material{} = material) do
    %{
      type: material.type,
      fingerprint: Pipelines.material_fingerprint(material),
      attributes: attributes(material)
    }
  end

  # A dependency material names the pipeline and stage it watches instead of a
  # url and a branch; those two live in type_specific_config, not in columns.
  defp attributes(material) do
    type_specific = material.type_specific_config || %{}

    %{
      url: material.url,
      destination: material.destination,
      filter: filter(material),
      invert_filter: false,
      name: type_specific["material_name"],
      auto_update: material.auto_update,
      branch: material.branch,
      username: material.username
    }
    |> put_if_present(:pipeline, type_specific["pipeline_name"])
    |> put_if_present(:stage, type_specific["stage_name"])
  end

  # GoCD answers `null` rather than an empty list when nothing is filtered.
  defp filter(material) do
    rules =
      Enum.map(material.filter_ignore || [], &%{type: "ignore", pattern: &1}) ++
        Enum.map(material.filter_include || [], &%{type: "include", pattern: &1})

    if rules == [], do: nil, else: rules
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
