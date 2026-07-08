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
              "MinAgents" => 1
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
  Auto-seeds Docker elastic agent profiles by name. Idempotent — skips profiles
  that already exist so new profiles are added without touching existing ones.

  Returns :ok.
  """
  @spec maybe_auto_seed_docker_profile() :: :ok
  def maybe_auto_seed_docker_profile do
    min_image = "ghcr.io/d-led/ex_gocd-agent:latest"
    java_image = "gocd/gocd-agent-docker-24.5.0"
    rust_elixir_image = "ghcr.io/d-led/ex_gocd-agent:rust-elixir"
    golang_image = "ghcr.io/d-led/ex_gocd-agent:golang"
    standard_image = "ghcr.io/d-led/ex_gocd-agent:standard"
    full_image = "ghcr.io/d-led/ex_gocd-agent:full"
    ubuntu_image = "gocd/gocd-agent-ubuntu-24.04"

    profiles = [
      %{
        name: "docker-no-resources",
        image: min_image,
        memory: "512m",
        cpu: "1.0",
        resource_images: %{}
      },
      %{
        name: "docker-default",
        image: java_image,
        memory: "2g",
        cpu: "2.0",
        resource_images: %{
          "java" => java_image,
          "gradle" => java_image,
          "git" => java_image,
          "docker" => java_image,
          "python" => java_image,
          "node" => java_image,
          "ruby" => java_image
        }
      },
      %{
        name: "docker-rust-elixir",
        image: rust_elixir_image,
        memory: "2g",
        cpu: "2.0",
        resource_images: %{
          "rust" => rust_elixir_image,
          "cargo" => rust_elixir_image,
          "elixir" => rust_elixir_image
        }
      },
      %{
        name: "docker-golang",
        image: golang_image,
        memory: "2g",
        cpu: "2.0",
        resource_images: %{
          "go" => golang_image,
          "golang" => golang_image
        }
      },
      %{
        name: "docker-gradle-official",
        image: ubuntu_image,
        memory: "4g",
        cpu: "2.0",
        resource_images: %{
          "java" => ubuntu_image,
          "gradle" => ubuntu_image,
          "git" => ubuntu_image,
          "docker" => ubuntu_image
        }
      },
      %{
        name: "docker-standard",
        image: standard_image,
        memory: "1g",
        cpu: "1.0",
        resource_images: %{
          "git" => standard_image,
          "make" => standard_image,
          "curl" => standard_image,
          "bash" => standard_image,
          "python" => standard_image,
          "node" => standard_image,
          "ruby" => standard_image
        }
      },
      %{
        name: "docker-full",
        image: full_image,
        memory: "4g",
        cpu: "2.0",
        resource_images: %{
          "java" => full_image,
          "gradle" => full_image,
          "go" => full_image,
          "golang" => full_image,
          "rust" => full_image,
          "cargo" => full_image,
          "elixir" => full_image,
          "git" => full_image,
          "docker" => full_image,
          "python" => full_image,
          "node" => full_image,
          "ruby" => full_image,
          "make" => full_image
        }
      }
    ]

    Enum.each(profiles, fn p ->
      unless repo_exists?(p.name) do
        %ElasticAgentProfile{}
        |> ElasticAgentProfile.changeset(%{
          name: p.name,
          plugin_id: "cd.go.contrib.elastic-agent.docker",
          cluster_profile_id: "docker-local",
          properties: %{
            "Image" => p.image,
            "MaxMemory" => p.memory,
            "MaxCPU" => p.cpu,
            "ResourceImages" => p.resource_images,
            "MinAgents" => 1
          }
        })
        |> Repo.insert()
      end
    end)

    :ok
  end

  defp repo_exists?(name) do
    Repo.exists?(from p in ElasticAgentProfile, where: p.name == ^name)
  end
end
