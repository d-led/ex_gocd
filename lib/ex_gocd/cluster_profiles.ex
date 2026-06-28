defmodule ExGoCD.ClusterProfiles do
  @moduledoc """
  Context for cluster profiles. Cluster profiles define the cluster
  configuration (e.g., Kubernetes API URL, credentials) that elastic
  agent profiles connect to.
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.ClusterProfiles.ClusterProfile
  alias ExGoCD.K8s

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

  @doc """
  Auto-discovers a local k3s cluster and seeds a "k3s-local" cluster profile
  if none exists. Idempotent: does nothing if a profile named "k3s-local"
  already exists or if k3s is not available.

  Returns `:ok` (seeded or already exists) or `:no_k3s` (cluster not found).
  """
  @spec maybe_auto_seed_k3s() :: :ok | :no_k3s
  def maybe_auto_seed_k3s do
    existing =
      Repo.exists?(from p in ClusterProfile, where: p.name == "k3s-local")

    if existing do
      :ok
    else
      case K8s.discover_local_k3s() do
        {:ok, config} ->
          %ClusterProfile{}
          |> ClusterProfile.changeset(%{
            name: "k3s-local",
            plugin_id: "ex_gocd.elasticagent.kubernetes",
            properties: %{
              "kubernetes_cluster_url" => config["server"],
              "bearer_token" => config["token"],
              "kubernetes_cluster_ca_cert" => config["ca_cert"],
              "namespace" => config["namespace"],
              "client_cert" => config["client_cert"],
              "client_key" => config["client_key"]
            }
          })
          |> Repo.insert()
          |> case do
            {:ok, _} -> :ok
            {:error, _} -> :ok
          end

        {:error, _} ->
          :no_k3s
      end
    end
  end

  @doc """
  Checks connectivity to a cluster profile's Kubernetes API.

  Returns `:ok` on success, `{:error, reason}` on failure
  (reason is a human-readable string), or `{:error, :incomplete}`
  when the profile is missing required fields.
  """
  @spec check_connection(ClusterProfile.t()) :: :ok | {:error, String.t() | :incomplete}
  def check_connection(%ClusterProfile{} = profile) do
    kubeconfig = ClusterProfile.kubeconfig_yaml(profile)

    if kubeconfig && kubeconfig != "" do
      ping_via_kubeconfig(kubeconfig, profile)
    else
      ping_via_fields(profile)
    end
  end

  defp ping_via_kubeconfig(kubeconfig, profile) do
    case K8s.from_kubeconfig(kubeconfig) do
      {:ok, conn} -> K8s.ping(conn, namespace: ClusterProfile.namespace(profile))
      {:error, reason} -> {:error, "Invalid kubeconfig: #{inspect(reason)}"}
    end
  end

  defp ping_via_fields(profile) do
    server = ClusterProfile.server_url(profile)
    token = ClusterProfile.bearer_token(profile)
    client_cert = ClusterProfile.client_cert(profile)
    client_key = ClusterProfile.client_key(profile)

    has_token = token != nil and token != ""

    has_cert =
      client_cert != nil and client_key != nil and client_cert != "" and client_key != ""

    if is_nil(server) or server == "" or not (has_token or has_cert) do
      {:error, :incomplete}
    else
      config = %{
        "server" => server,
        "token" => token,
        "ca_cert" => ClusterProfile.ca_cert(profile),
        "namespace" => ClusterProfile.namespace(profile),
        "client_cert" => client_cert,
        "client_key" => client_key
      }

      case K8s.from_config(config) do
        {:ok, conn} -> K8s.ping(conn, namespace: ClusterProfile.namespace(profile))
        {:error, reason} -> {:error, "Invalid config: #{inspect(reason)}"}
      end
    end
  end

  @doc "Same as check_connection/1 but never raises — catches all errors."
  def safe_check_connection(%ClusterProfile{} = profile) do
    check_connection(profile)
  rescue
    e -> {:error, "Internal: #{Exception.message(e)}"}
  end
end
