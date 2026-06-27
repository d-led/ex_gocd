defmodule ExGoCD.PackageRepositories do
  @moduledoc """
  Context for package repositories (e.g., Docker registries, Maven repos).
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.PackageRepositories.PackageRepository

  def list_repos, do: Repo.all(PackageRepository)
  def get_repo!(id), do: Repo.get!(PackageRepository, id)
  def get_repo(id), do: Repo.get(PackageRepository, id)

  def create_repo(attrs \\ %{}) do
    %PackageRepository{}
    |> PackageRepository.changeset(attrs)
    |> Repo.insert()
  end

  def update_repo(%PackageRepository{} = repo, attrs) do
    repo |> PackageRepository.changeset(attrs) |> Repo.update()
  end

  def delete_repo(%PackageRepository{} = repo), do: Repo.delete(repo)

  def list_by_plugin(plugin_id) do
    Repo.all(from r in PackageRepository, where: r.plugin_id == ^plugin_id)
  end
end
