defmodule ExGoCD.Repo.Migrations.CreateConfigVersions do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:config_versions) do
      add :config_hash, :string, null: false
      add :config_json, :map, null: false
      add :config_xml, :text
      add :changed_by, :string
      add :change_reason, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create_if_not_exists index(:config_versions, [:inserted_at])
    create_if_not_exists unique_index(:config_versions, [:config_hash])
  end
end
