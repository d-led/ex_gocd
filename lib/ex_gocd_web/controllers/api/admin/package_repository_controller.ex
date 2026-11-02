defmodule ExGoCDWeb.API.Admin.PackageRepositoryController do
  use ExGoCDWeb, :controller
  alias ExGoCD.PackageRepositories

  def index(conn, _params), do: render(conn, :index, repos: PackageRepositories.list_repos())

  def show(conn, %{"id" => id}) do
    case PackageRepositories.get_repo(id) do
      nil -> not_found(conn, "Package repository", id)
      repo -> render(conn, :show, repo: repo)
    end
  end

  def create(conn, %{"package_repository" => params}) do
    case PackageRepositories.create_repo(params) do
      {:ok, repo} ->
        conn |> put_status(:created) |> render(:show, repo: repo)

      {:error, cs} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "package_repository" => params}) do
    case PackageRepositories.get_repo(id) do
      nil ->
        not_found(conn, "Package repository", id)

      repo ->
        case PackageRepositories.update_repo(repo, params) do
          {:ok, updated} ->
            render(conn, :show, repo: updated)

          {:error, cs} ->
            conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case PackageRepositories.get_repo(id) do
      nil ->
        not_found(conn, "Package repository", id)

      repo ->
        PackageRepositories.delete_repo(repo)
        conn |> put_status(:no_content) |> json(%{message: "Deleted"})
    end
  end
end
