defmodule ExGoCDWeb.API.Admin.PackageRepositoryController do
  use ExGoCDWeb, :controller
  alias ExGoCD.PackageRepositories

  def index(conn, _params), do: render(conn, :index, repos: PackageRepositories.list_repos())
  def show(conn, %{"id" => id}), do: render(conn, :show, repo: PackageRepositories.get_repo!(id))

  def create(conn, %{"package_repository" => params}) do
    case PackageRepositories.create_repo(params) do
      {:ok, repo} -> conn |> put_status(:created) |> render(:show, repo: repo)
      {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "package_repository" => params}) do
    case PackageRepositories.update_repo(PackageRepositories.get_repo!(id), params) do
      {:ok, repo} -> render(conn, :show, repo: repo)
      {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def delete(conn, %{"id" => id}) do
    PackageRepositories.get_repo!(id) |> PackageRepositories.delete_repo()
    conn |> put_status(:no_content) |> json(%{message: "Deleted"})
  end

  defp changeset_errors(cs), do: Ecto.Changeset.traverse_errors(cs, fn {m, o} -> Enum.reduce(o, m, fn {k, v}, a -> String.replace(a, "%{#{k}}", to_string(v)) end) end)
end
