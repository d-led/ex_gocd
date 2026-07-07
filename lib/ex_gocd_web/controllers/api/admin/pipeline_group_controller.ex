defmodule ExGoCDWeb.API.Admin.PipelineGroupController do
  @moduledoc """
  Pipeline groups admin API. GoCD parity: CRUD /go/api/admin/pipeline_groups.
  In ex_gocd, pipeline groups are managed via the `group` field on Pipeline.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.{Pipelines, Repo}
  alias ExGoCD.Pipelines.Pipeline
  import Ecto.Query

  @doc "GET /api/admin/pipeline_groups — list all pipeline groups"
  def index(conn, _params) do
    pipelines = Repo.all(Pipeline)
    groups = pipelines |> Enum.map(& &1.group) |> Enum.uniq() |> Enum.sort()

    json(conn, %{
      groups:
        Enum.map(groups, fn g ->
          %{name: g, pipelines: Enum.filter(pipelines, &(&1.group == g)) |> Enum.map(& &1.name)}
        end)
    })
  end

  @doc "GET /api/admin/pipeline_groups/:name"
  def show(conn, %{"name" => name}) do
    pipelines = Repo.all(from p in Pipeline, where: p.group == ^name)

    if pipelines == [] do
      conn |> put_status(:not_found) |> json(%{error: "Pipeline group not found"})
    else
      json(conn, %{name: name, pipelines: Enum.map(pipelines, & &1.name)})
    end
  end

  @doc "POST /api/admin/pipeline_groups — create a pipeline group (sets group on pipelines)"
  def create(conn, %{"name" => name, "pipelines" => pipeline_names})
      when is_list(pipeline_names) do
    updated =
      Enum.reduce(pipeline_names, [], fn pname, acc ->
        case Repo.get_by(Pipeline, name: pname) do
          nil ->
            acc

          p ->
            {:ok, _} = Pipelines.update_pipeline(p, %{group: name})
            [pname | acc]
        end
      end)

    json(conn, %{name: name, pipelines: Enum.reverse(updated)})
  end

  def create(conn, %{"name" => _name}) do
    json(conn, %{name: Map.get(conn.params, "name"), pipelines: []})
  end

  @doc "DELETE /api/admin/pipeline_groups/:name"
  def delete(conn, %{"name" => name}) do
    pipelines = Repo.all(from p in Pipeline, where: p.group == ^name)
    Enum.each(pipelines, fn p -> Pipelines.update_pipeline(p, %{group: "defaultGroup"}) end)
    json(conn, %{message: "Pipeline group '#{name}' removed."})
  end
end
