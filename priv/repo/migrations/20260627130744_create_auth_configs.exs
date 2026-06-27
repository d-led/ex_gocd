defmodule ExGoCD.Repo.Migrations.CreateAuthConfigs do
  use Ecto.Migration

  def change do
    create table(:auth_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plugin_id, :string, null: false
      add :properties, :map, default: %{}

      timestamps()
    end

    create unique_index(:auth_configs, [:plugin_id])
  end
end
