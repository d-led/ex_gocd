defmodule ExGoCDWeb.PipelineGroupController do
  use ExGoCDWeb, :controller

  import Ecto.Query

  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo

  @doc """
  GET /go/api/admin/pipeline_groups — lists all pipeline groups.
  """
  def index(conn, _params) do
    groups =
      Repo.all(
        from p in Pipeline,
          group_by: p.group,
          select: %{name: p.group, pipeline_count: count(p.id)}
      )
      |> Enum.sort_by(& &1.name)

    json(conn, groups)
  end

  @doc """
  GET /go/api/admin/pipeline_groups/:name — shows a pipeline group with its pipelines.
  """
  def show(conn, %{"name" => name}) do
    pipelines =
      Repo.all(
        from p in Pipeline,
          where: p.group == ^name,
          select: %{name: p.name, label_template: p.label_template}
      )

    if pipelines == [] do
      conn |> put_status(:not_found) |> json(%{message: "Pipeline group not found"})
    else
      json(conn, %{name: name, pipelines: pipelines})
    end
  end

  @doc """
  POST /go/api/admin/pipeline_groups — creates a new pipeline group.
  Since groups are implicit (defined by the group field on pipelines),
  this is a no-op that returns success if the group name is valid.
  """
  def create(conn, %{"name" => name}) when is_binary(name) and name != "" do
    json(conn, %{name: name, message: "Pipeline group '#{name}' is available for pipelines"})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{message: "Pipeline group name is required"})
  end

  @doc """
  PUT /go/api/admin/pipeline_groups/:name — updates a pipeline group
  (moves all pipelines with old group name to new group name).
  """
  def update(conn, %{"name" => old_name, "group" => %{"name" => new_name}}) do
    {count, _} =
      Repo.update_all(
        from(p in Pipeline, where: p.group == ^old_name),
        set: [group: new_name]
      )

    json(conn, %{name: new_name, pipelines_moved: count})
  end

  def update(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{message: "New group name is required (body: {\"group\": {\"name\": \"...\"}})"})
  end

  @doc """
  DELETE /go/api/admin/pipeline_groups/:name — deletes a pipeline group
  (moves all pipelines to 'default' group).
  """
  def delete(conn, %{"name" => name}) do
    {count, _} =
      Repo.update_all(
        from(p in Pipeline, where: p.group == ^name),
        set: [group: "default"]
      )

    json(conn, %{message: "Moved #{count} pipeline(s) from '#{name}' to 'default' group"})
  end
end
