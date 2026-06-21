defmodule ExGoCD.Repo.Migrations.AddJobInstanceIdToAgentJobRuns do
  use Ecto.Migration

  def change do
    alter table(:agent_job_runs) do
      add :job_instance_id, references(:job_instances, on_delete: :nilify_all)
    end

    create index(:agent_job_runs, [:job_instance_id])
  end
end
