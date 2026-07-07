defmodule ExGoCDWeb.SCMController do
  use ExGoCDWeb, :controller

  import Ecto.Query

  alias ExGoCD.Pipelines.Material
  alias ExGoCD.Repo

  @doc """
  GET /go/api/scms — lists all SCM materials across all pipelines.
  """
  def index(conn, _params) do
    materials =
      Repo.all(
        from m in Material,
          join: p in assoc(m, :pipeline),
          where: m.type == "git" or m.type == "hg" or m.type == "svn",
          select: %{
            id: m.id,
            name: p.name,
            type: m.type,
            url: m.url,
            branch: m.branch,
            pipeline_name: p.name,
            auto_update: m.auto_update
          }
      )

    json(conn, materials)
  end

  @doc """
  GET /go/api/scms/:id — shows a single SCM material by ID.
  """
  def show(conn, %{"id" => id}) do
    case Repo.get(Material, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "SCM not found"})

      material ->
        json(conn, %{
          id: material.id,
          type: material.type,
          url: material.url,
          branch: material.branch,
          auto_update: material.auto_update
        })
    end
  end
end
