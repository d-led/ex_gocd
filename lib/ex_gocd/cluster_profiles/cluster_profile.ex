defmodule ExGoCD.ClusterProfiles.ClusterProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "cluster_profiles" do
    field :name, :string
    field :plugin_id, :string, default: "cd.go.contrib.elasticagent.kubernetes"
    field :properties, :map, default: %{}
    timestamps()
  end

  @required_fields ~w(name plugin_id)a
  @optional_fields ~w(properties)a

  # Virtual fields for UI — synced to/from properties
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc "Returns the server URL from properties."
  def server_url(%__MODULE__{properties: props}), do: Map.get(props, "kubernetes_cluster_url") || Map.get(props, "server_url")
  def server_url(_), do: nil

  @doc "Returns the bearer token from properties."
  def bearer_token(%__MODULE__{properties: props}), do: Map.get(props, "bearer_token")
  def bearer_token(_), do: nil

  @doc "Returns the CA cert from properties."
  def ca_cert(%__MODULE__{properties: props}), do: Map.get(props, "kubernetes_cluster_ca_cert") || Map.get(props, "ca_cert")
  def ca_cert(_), do: nil

  @doc "Returns the namespace from properties."
  def namespace(%__MODULE__{properties: props}), do: Map.get(props, "namespace", "default")
  def namespace(_), do: "default"
end
