defmodule ExGoCD.Repo.Migrations.CreateAgentJobRunTransitions do
  use Ecto.Migration

  def change do
    create table(:agent_job_run_transitions) do
      add :agent_job_run_id, references(:agent_job_runs, on_delete: :delete_all), null: false
      add :state, :string, null: false
      add :changed_at, :utc_datetime, null: false
    end

    create index(:agent_job_run_transitions, [:agent_job_run_id, :changed_at])
  end
end
