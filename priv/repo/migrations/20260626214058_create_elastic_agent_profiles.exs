defmodule ExGoCD.Repo.Migrations.CreateElasticAgentProfiles do
  use Ecto.Migration

  def change do
    create table(:elastic_agent_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plugin_id, :string, null: false
      add :cluster_profile_id, :string
      add :properties, :map, default: %{}

      timestamps()
    end

    create index(:elastic_agent_profiles, [:plugin_id])
    create index(:elastic_agent_profiles, [:cluster_profile_id])
  end
end
