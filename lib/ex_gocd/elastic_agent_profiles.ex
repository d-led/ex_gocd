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
  Auto-seeds Docker elastic agent profiles if none exist. Idempotent.

  Seeds four profiles, each mapping different resource sets to the right image:

  | Profile              | Resources                  | Image                                    | Size   |
  |----------------------|----------------------------|------------------------------------------|--------|
  | docker-no-resources  | (none — default)           | ghcr.io/d-led/ex_gocd-agent:latest       | ~55MB  |
  | docker-default       | java, gradle, git, docker, | gocd/gocd-agent-docker-24.5.0            | ~200MB |
  |                      | python, node, ruby         |                                          |        |
  | docker-rust-elixir   | rust, cargo, elixir        | ghcr.io/d-led/ex_gocd-agent:rust-elixir  | ~788MB |
  | docker-golang        | go, golang                 | ghcr.io/d-led/ex_gocd-agent:golang       | ~487MB |

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
      min_image = "ghcr.io/d-led/ex_gocd-agent:latest"
      java_image = "gocd/gocd-agent-docker-24.5.0"
      rust_elixir_image = "ghcr.io/d-led/ex_gocd-agent:rust-elixir"
      golang_image = "ghcr.io/d-led/ex_gocd-agent:golang"

      # Profile 1: No resources — lightweight, no Java needed
      %ElasticAgentProfile{}
      |> ElasticAgentProfile.changeset(%{
        name: "docker-no-resources",
        plugin_id: "cd.go.contrib.elastic-agent.docker",
        cluster_profile_id: "docker-local",
        properties: %{
          "Image" => min_image,
          "MaxMemory" => "512m",
          "MaxCPU" => "1.0",
          "MinAgents" => 0
        }
      })
      |> Repo.insert()

      # Profile 2: Java/Gradle — needs JVM, handles most common tools
      %ElasticAgentProfile{}
      |> ElasticAgentProfile.changeset(%{
        name: "docker-default",
        plugin_id: "cd.go.contrib.elastic-agent.docker",
        cluster_profile_id: "docker-local",
        properties: %{
          "Image" => java_image,
          "MaxMemory" => "2g",
          "MaxCPU" => "2.0",
          "ResourceImages" => %{
            "java" => java_image,
            "gradle" => java_image,
            "git" => java_image,
            "docker" => java_image,
            "python" => java_image,
            "node" => java_image,
            "ruby" => java_image
          },
          "MinAgents" => 0
        }
      })
      |> Repo.insert()

      # Profile 3: Rust + Elixir — includes Rust, Cargo, Elixir, Erlang, build tools
      %ElasticAgentProfile{}
      |> ElasticAgentProfile.changeset(%{
        name: "docker-rust-elixir",
        plugin_id: "cd.go.contrib.elastic-agent.docker",
        cluster_profile_id: "docker-local",
        properties: %{
          "Image" => rust_elixir_image,
          "MaxMemory" => "2g",
          "MaxCPU" => "2.0",
          "ResourceImages" => %{
            "rust" => rust_elixir_image,
            "cargo" => rust_elixir_image,
            "elixir" => rust_elixir_image
          },
          "MinAgents" => 0
        }
      })
      |> Repo.insert()

      # Profile 4: Go — lightweight Go compiler + build-base for CGO
      %ElasticAgentProfile{}
      |> ElasticAgentProfile.changeset(%{
        name: "docker-golang",
        plugin_id: "cd.go.contrib.elastic-agent.docker",
        cluster_profile_id: "docker-local",
        properties: %{
          "Image" => golang_image,
          "MaxMemory" => "2g",
          "MaxCPU" => "2.0",
          "ResourceImages" => %{
            "go" => golang_image,
            "golang" => golang_image
          },
          "MinAgents" => 0
        }
      })
      |> Repo.insert()

      :ok
    end
  end
end
