defmodule ExGoCD.Repo.Migrations.AddConsoleLogToAgentJobRuns do
  use Ecto.Migration

  def change do
    alter table(:agent_job_runs) do
      add :console_log, :text, default: ""
    end
  end
end
