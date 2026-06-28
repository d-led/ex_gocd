defmodule ExGoCD.Repo.Migrations.CreateAgentSnapshots do
  use Ecto.Migration

  def change do
    create table(:agent_snapshots) do
      add :total, :integer, null: false
      add :idle, :integer, null: false
      add :building, :integer, null: false
      add :disabled, :integer, null: false, default: 0
      add :lost_contact, :integer, null: false, default: 0
      add :elastic, :integer, null: false, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
