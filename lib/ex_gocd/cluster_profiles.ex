defmodule ExGoCD.ClusterProfiles do
  @moduledoc """
  Context for cluster profiles. Cluster profiles define the cluster
  configuration (e.g., Kubernetes API URL, credentials) that elastic
  agent profiles connect to.
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.ClusterProfiles.ClusterProfile

  @doc "Returns all cluster profiles."
  def list_profiles do
    Repo.all(ClusterProfile)
  end

  @doc "Gets a profile by id."
  def get_profile!(id), do: Repo.get!(ClusterProfile, id)
  def get_profile(id), do: Repo.get(ClusterProfile, id)

  @doc "Creates a profile."
  def create_profile(attrs \\ %{}) do
    %ClusterProfile{}
    |> ClusterProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a profile."
  def update_profile(%ClusterProfile{} = profile, attrs) do
    profile
    |> ClusterProfile.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a profile."
  def delete_profile(%ClusterProfile{} = profile) do
    Repo.delete(profile)
  end

  @doc "Finds profiles by plugin_id."
  def list_by_plugin(plugin_id) do
    Repo.all(from p in ClusterProfile, where: p.plugin_id == ^plugin_id)
  end
end
