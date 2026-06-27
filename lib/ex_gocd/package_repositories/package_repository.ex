defmodule ExGoCD.PackageRepositories.PackageRepository do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "package_repositories" do
    field :name, :string
    field :plugin_id, :string
    field :configuration, :map, default: %{}

    timestamps()
  end

  @required_fields ~w(name plugin_id)a
  @optional_fields ~w(configuration)a

  def changeset(repo, attrs) do
    repo
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
