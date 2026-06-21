defmodule ExGoCD.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    # Agents table - persistent configuration only
    # Based on: config/config-api/.../Agent.java
    create table(:agents) do
      # Core identification
      add :uuid, :string, null: false
      add :hostname, :string, null: false
      # Note: GoCD uses "ipaddress" not "ip_address"
      add :ipaddress, :string, null: false

      # Elastic agent support
      add :elastic_agent_id, :string
      add :elastic_plugin_id, :string

      # Management flags
      add :disabled, :boolean, default: false, null: false
      # Soft delete
      add :deleted, :boolean, default: false, null: false

      # Agent capabilities and environment membership
      # Note: GoCD stores these as comma-separated strings in DB
      # We use arrays for PostgreSQL convenience, but API maintains string compatibility
      add :environments, {:array, :string}, default: []
      add :resources, {:array, :string}, default: []

      # Registration cookie
      add :cookie, :string

      timestamps(type: :utc_datetime)
    end

    # Indexes for queries and constraints
    create unique_index(:agents, [:uuid])
    create index(:agents, [:hostname])
    create index(:agents, [:disabled])
    create index(:agents, [:deleted])
    # For array queries
    create index(:agents, [:environments], using: "GIN")
    create index(:agents, [:resources], using: "GIN")
  end
end
