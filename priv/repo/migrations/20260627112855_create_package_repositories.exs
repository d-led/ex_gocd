defmodule ExGoCD.Repo.Migrations.CreatePackageRepositories do
  use Ecto.Migration

  def change do
    create table(:package_repositories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :plugin_id, :string, null: false
      add :configuration, :map, default: %{}

      timestamps()
    end

    create unique_index(:package_repositories, [:name])
  end
end
