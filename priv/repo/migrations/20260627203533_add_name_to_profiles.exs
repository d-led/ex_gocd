defmodule ExGoCD.Repo.Migrations.AddNameToProfiles do
  use Ecto.Migration

  def change do
    alter table(:cluster_profiles) do
      add :name, :string
    end

    alter table(:elastic_agent_profiles) do
      add :name, :string
    end

    create index(:cluster_profiles, [:name])
    create index(:elastic_agent_profiles, [:name])
  end
end
