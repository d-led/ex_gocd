defmodule ExGoCD.Repo.Migrations.AddArtifactRetentionRunsToStages do
  use Ecto.Migration

  def change do
    alter table(:stages) do
      add :artifact_retention_runs, :integer, default: 1, null: false
    end
  end
end
