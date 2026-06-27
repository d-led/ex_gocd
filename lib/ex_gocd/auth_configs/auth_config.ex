defmodule ExGoCD.AuthConfigs.AuthConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "auth_configs" do
    field :plugin_id, :string
    field :properties, :map, default: %{}
    timestamps()
  end

  @required_fields ~w(plugin_id)a
  @optional_fields ~w(properties)a

  def changeset(config, attrs) do
    config
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:plugin_id)
  end
end
