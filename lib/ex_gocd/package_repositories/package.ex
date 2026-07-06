defmodule ExGoCD.PackageRepositories.Package do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "packages" do
    field :name, :string
    field :package_type, :string, default: "generic"
    field :configuration, :map, default: %{}
    belongs_to :package_repository, ExGoCD.PackageRepositories.PackageRepository

    timestamps()
  end

  @required_fields ~w(name package_repository_id)a
  @optional_fields ~w(package_type configuration)a

  def changeset(pkg, attrs) do
    pkg
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :package_repository_id])
  end
end
