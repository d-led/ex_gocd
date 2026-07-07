defmodule ExGoCD.ElasticAgentProfiles do
  @moduledoc """
  Context for elastic agent profiles. Elastic agent profiles define
  how elastic agents (e.g., Kubernetes pods) are configured for a
  specific plugin type.
  """

  import Ecto.Query, warn: false
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile
  alias ExGoCD.Repo

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

  @doc """
  Auto-seeds a default elastic agent profile for the k3s-local cluster
  if no profiles exist and the cluster is present. Idempotent.

  Returns `:ok` (seeded, already exists, or no cluster) or `:no_cluster`.
  """
  @spec maybe_auto_seed_default_profile() :: :ok | :no_cluster
  def maybe_auto_seed_default_profile do
    # Don't seed if profiles already exist (user may have custom config)
    if Repo.exists?(ElasticAgentProfile) do
      :ok
    else
      case Repo.get_by(ExGoCD.ClusterProfiles.ClusterProfile, name: "k3s-local") do
        nil ->
          :no_cluster

        cluster ->
          %ElasticAgentProfile{}
          |> ElasticAgentProfile.changeset(%{
            name: "default",
            plugin_id: "ex_gocd.elasticagent.kubernetes",
            cluster_profile_id: cluster.id,
            properties: %{
              "Image" => "gocd/gocd-agent-docker-24.5.0",
              "MaxMemory" => "2Gi",
              "MaxCPU" => "2",
              "MinMemory" => "1Gi",
              "MinCPU" => "1",
              "ImagePullPolicy" => "IfNotPresent",
              "Privileged" => "false",
              "MinAgents" => 0
            }
          })
          |> Repo.insert()
          |> case do
            {:ok, _} -> :ok
            {:error, _} -> :ok
          end
      end
    end
  end

  @doc """
  Auto-seeds a default Docker elastic agent profile if none exists.
  Uses local Docker socket. Idempotent.

  Returns :ok (seeded or already exists).
  """
  @spec maybe_auto_seed_docker_profile() :: :ok
  def maybe_auto_seed_docker_profile do
    existing =
      Repo.exists?(
        from p in ElasticAgentProfile,
          where: p.plugin_id == "cd.go.contrib.elastic-agent.docker"
      )

    if existing do
      :ok
    else
      %ElasticAgentProfile{}
      |> ElasticAgentProfile.changeset(%{
        name: "docker-default",
        plugin_id: "cd.go.contrib.elastic-agent.docker",
        cluster_profile_id: "docker-local",
        properties: %{
          "Image" => "gocd/gocd-agent-docker-24.5.0",
          "MaxMemory" => "2g",
          "MaxCPU" => "2.0",
          "ResourceImages" => %{
            "java" => "gocd/gocd-agent-docker-24.5.0",
            "gradle" => "gocd/gocd-agent-docker-24.5.0",
            "python" => "gocd/gocd-agent-docker-24.5.0",
            "node" => "gocd/gocd-agent-docker-24.5.0",
            "ruby" => "gocd/gocd-agent-docker-24.5.0",
            "docker" => "gocd/gocd-agent-docker-24.5.0"
          },
          "MinAgents" => 0
        }
      })
      |> Repo.insert()
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end
end
