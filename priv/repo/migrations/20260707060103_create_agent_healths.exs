defmodule ExGoCD.Repo.Migrations.CreateAgentHealths do
  use Ecto.Migration

  def change do
    create table(:agent_healths, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_uuid, :string, null: false
      add :cpu_percent, :float
      add :memory_mb, :integer
      add :disk_free_mb, :integer
      add :disk_total_mb, :integer
      add :os, :string
      add :uptime_seconds, :integer
      add :reported_at, :utc_datetime
      timestamps(updated_at: false)
    end

    create index(:agent_healths, [:agent_uuid])
    create index(:agent_healths, [:agent_uuid, :reported_at])
  end
end
