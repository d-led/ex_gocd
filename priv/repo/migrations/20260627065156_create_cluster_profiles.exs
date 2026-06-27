defmodule ExGoCD.Repo.Migrations.CreateClusterProfiles do
  use Ecto.Migration

  def change do
    create table(:cluster_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plugin_id, :string, null: false
      add :properties, :map, default: %{}

      timestamps()
    end

    create index(:cluster_profiles, [:plugin_id])
  end
end
