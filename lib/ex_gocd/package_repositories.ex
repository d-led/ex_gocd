defmodule ExGoCD.PackageRepositories do
  @moduledoc """
  Context for package repositories (e.g., Docker registries, Maven repos).
  """

  import Ecto.Query, warn: false
  alias ExGoCD.PackageRepositories.PackageRepository
  alias ExGoCD.Repo

  def list_repos, do: Repo.all(PackageRepository)
  def get_repo!(id), do: Repo.get!(PackageRepository, id)

  @doc """
  Fetches a repository, or `nil` when no repository has that id.

  The id arrives from a path, so it is whatever a caller typed; `Repo.get/2`
  raises `Ecto.Query.CastError` for a word, which turns a mistyped path into a
  500. A word simply names nothing.
  """
  def get_repo(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(PackageRepository, uuid)
      :error -> nil
    end
  end

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
