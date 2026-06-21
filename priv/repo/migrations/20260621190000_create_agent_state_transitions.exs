defmodule ExGoCD.Repo.Migrations.CreateAgentStateTransitions do
  use Ecto.Migration

  def change do
    create table(:agent_state_transitions) do
      add :agent_uuid, :string, null: false
      add :from_state, :string
      add :to_state, :string, null: false
      add :transitioned_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:agent_state_transitions, [:agent_uuid])
    create index(:agent_state_transitions, [:transitioned_at])
    create index(:agent_state_transitions, [:agent_uuid, :transitioned_at])
  end
end
