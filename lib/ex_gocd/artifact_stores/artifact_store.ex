defmodule ExGoCD.ArtifactStores.ArtifactStore do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "artifact_stores" do
    field :plugin_id, :string
    field :properties, :map, default: %{}
    timestamps()
  end

  @required_fields ~w(plugin_id)a
  @optional_fields ~w(properties)a

  def changeset(store, attrs) do
    store
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
