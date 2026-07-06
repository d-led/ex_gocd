defmodule ExGoCD.Repo.Migrations.CreatePackages do
  use Ecto.Migration

  def change do
    create table(:packages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :package_type, :string, default: "generic"
      add :configuration, :map, default: %{}
      add :package_repository_id, references(:package_repositories, type: :binary_id), null: false
      timestamps()
    end

    create unique_index(:packages, [:name, :package_repository_id])
  end
end
