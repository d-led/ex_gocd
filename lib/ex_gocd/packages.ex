defmodule ExGoCD.Packages do
  @moduledoc """
  Context for packages within package repositories.
  GoCD parity: Packages API v2.
  """
  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.PackageRepositories.Package

  def list_packages, do: Repo.all(Package) |> Repo.preload(:package_repository)
  def get_package!(id), do: Repo.get!(Package, id) |> Repo.preload(:package_repository)

  def get_package(id) do
    case Repo.get(Package, id) do
      nil -> nil
      p -> Repo.preload(p, :package_repository)
    end
  end

  def list_by_repo(repo_id) do
    Repo.all(from p in Package, where: p.package_repository_id == ^repo_id)
  end

  def create_package(attrs \\ %{}) do
    %Package{}
    |> Package.changeset(attrs)
    |> Repo.insert()
  end

  def update_package(%Package{} = pkg, attrs) do
    pkg |> Package.changeset(attrs) |> Repo.update()
  end

  def delete_package(%Package{} = pkg), do: Repo.delete(pkg)
end
