defmodule ExGoCD.ElasticAgentProfiles.ElasticAgentProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "elastic_agent_profiles" do
    field :plugin_id, :string
    field :cluster_profile_id, :string
    field :properties, :map, default: %{}

    timestamps()
  end

  @required_fields ~w(plugin_id)a
  @optional_fields ~w(cluster_profile_id properties)a

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
