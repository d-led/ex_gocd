defmodule ExGoCD.Repo.Migrations.AddEnvironmentVariablesToAgentJobRuns do
  use Ecto.Migration

  def change do
    alter table(:agent_job_runs) do
      add :environment_variables, :map, default: %{}
    end
  end
end
