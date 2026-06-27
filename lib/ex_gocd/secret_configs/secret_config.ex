defmodule ExGoCD.SecretConfigs.SecretConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "secret_configs" do
    field :name, :string
    field :plugin_id, :string
    field :configuration, :map, default: %{}
    field :description, :string

    timestamps()
  end

  @required_fields ~w(name plugin_id)a
  @optional_fields ~w(configuration description)a

  def changeset(config, attrs) do
    config
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
