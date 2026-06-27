defmodule ExGoCD.ArtifactStores do
  @moduledoc "Context for artifact store configurations (S3, GCS, local disk, etc.)."
  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.ArtifactStores.ArtifactStore

  def list_stores, do: Repo.all(ArtifactStore)
  def get_store!(id), do: Repo.get!(ArtifactStore, id)
  def get_store(id), do: Repo.get(ArtifactStore, id)

  def create_store(attrs \\ %{}) do
    %ArtifactStore{} |> ArtifactStore.changeset(attrs) |> Repo.insert()
  end

  def update_store(%ArtifactStore{} = store, attrs) do
    store |> ArtifactStore.changeset(attrs) |> Repo.update()
  end

  def delete_store(%ArtifactStore{} = store), do: Repo.delete(store)
end
