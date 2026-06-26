defmodule ExGoCD.ElasticAgentProfiles do
  @moduledoc """
  Context for elastic agent profiles. Elastic agent profiles define
  how elastic agents (e.g., Kubernetes pods) are configured for a
  specific plugin type.
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile

  @doc "Returns all elastic agent profiles."
  def list_profiles do
    Repo.all(ElasticAgentProfile)
  end

  @doc "Gets a profile by id."
  def get_profile!(id), do: Repo.get!(ElasticAgentProfile, id)
  def get_profile(id), do: Repo.get(ElasticAgentProfile, id)

  @doc "Creates a profile."
  def create_profile(attrs \\ %{}) do
    %ElasticAgentProfile{}
    |> ElasticAgentProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a profile."
  def update_profile(%ElasticAgentProfile{} = profile, attrs) do
    profile
    |> ElasticAgentProfile.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a profile."
  def delete_profile(%ElasticAgentProfile{} = profile) do
    Repo.delete(profile)
  end

  @doc "Finds profiles by plugin_id."
  def list_by_plugin(plugin_id) do
    Repo.all(from p in ElasticAgentProfile, where: p.plugin_id == ^plugin_id)
  end
end
