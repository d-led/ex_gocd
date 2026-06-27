defmodule ExGoCD.ElasticAgentProfiles.ElasticAgentProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "elastic_agent_profiles" do
    field :name, :string
    field :plugin_id, :string, default: "cd.go.contrib.elasticagent.kubernetes"
    field :cluster_profile_id, :string
    field :properties, :map, default: %{}

    timestamps()
  end

  @required_fields ~w(name plugin_id cluster_profile_id)a
  @optional_fields ~w(properties)a

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  # ---- Property accessors (mirrors GoCD's kubernetes elastic agent profile) ----

  @doc "Docker image for the agent pod."
  def image(%__MODULE__{properties: props}),
    do: Map.get(props, "Image", "gocd/gocd-agent-docker-24.5.0")

  def image(_), do: "gocd/gocd-agent-docker-24.5.0"

  @doc "Memory limit (e.g. 2Gi)."
  def max_memory(%__MODULE__{properties: props}), do: Map.get(props, "MaxMemory", "2Gi")
  def max_memory(_), do: "2Gi"

  @doc "CPU limit (e.g. 2)."
  def max_cpu(%__MODULE__{properties: props}), do: Map.get(props, "MaxCPU", "2")
  def max_cpu(_), do: "2"

  @doc "Memory request."
  def min_memory(%__MODULE__{properties: props}), do: Map.get(props, "MinMemory", "1Gi")
  def min_memory(_), do: "1Gi"

  @doc "CPU request."
  def min_cpu(%__MODULE__{properties: props}), do: Map.get(props, "MinCPU", "1")
  def min_cpu(_), do: "1"

  @doc "Image pull policy: Always, IfNotPresent, Never."
  def image_pull_policy(%__MODULE__{properties: props}),
    do: Map.get(props, "ImagePullPolicy", "IfNotPresent")

  def image_pull_policy(_), do: "IfNotPresent"

  @doc "Run pod as privileged."
  def privileged(%__MODULE__{properties: props}), do: Map.get(props, "Privileged", "false")
  def privileged(_), do: "false"

  @doc "Environment variables for the agent pod."
  def env_vars(%__MODULE__{properties: props}), do: Map.get(props, "Environment", [])
  def env_vars(_), do: []

  @doc "Pod labels."
  def pod_labels(%__MODULE__{properties: props}), do: Map.get(props, "PodLabels", %{})
  def pod_labels(_), do: %{}

  @doc "Service account name."
  def service_account(%__MODULE__{properties: props}), do: Map.get(props, "ServiceAccount", "")
  def service_account(_), do: ""
end
