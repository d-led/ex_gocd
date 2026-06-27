defmodule ExGoCD.Repo.Migrations.CreateSecretConfigs do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:secret_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :plugin_id, :string, null: false
      add :configuration, :map, default: %{}
      add :description, :text

      timestamps()
    end

    create_if_not_exists unique_index(:secret_configs, [:name])
  end
end
