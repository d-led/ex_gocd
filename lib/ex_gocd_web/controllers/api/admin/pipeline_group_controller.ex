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

  @doc """
  PUT /api/admin/pipeline_groups/:name — renames a group, moving every pipeline
  in it.

  The new name is nested under `group` in the body: a body key `name` would be
  overwritten by the name in the path.
  """
  def update(conn, %{"name" => current, "group" => %{"name" => new_name}})
      when is_binary(new_name) and new_name != "" do
    if exists?(current) do
      {_count, _} =
        Repo.update_all(
          from(p in Pipeline, where: p.group == ^current),
          set: [group: new_name]
        )

      json(conn, group_json(new_name))
    else
      conn |> put_status(:not_found) |> json(%{error: "Pipeline group not found"})
    end
  end

  def update(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: ~S|New group name is required (body: {"group": {"name": "..."}})|})
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

  defp exists?(name), do: Repo.exists?(from p in Pipeline, where: p.group == ^name)

  defp group_json(name) do
    pipelines =
      from(p in Pipeline, where: p.group == ^name, select: p.name)
      |> Repo.all()
      |> Enum.sort()

    %{name: name, pipelines: pipelines}
  end
end
