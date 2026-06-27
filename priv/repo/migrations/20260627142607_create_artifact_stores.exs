defmodule ExGoCD.Repo.Migrations.CreateArtifactStores do
  use Ecto.Migration

  def change do
    create table(:artifact_stores, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plugin_id, :string, null: false
      add :properties, :map, default: %{}

      timestamps()
    end
  end
end
