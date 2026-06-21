defmodule ExGoCD.Repo.Migrations.CreateAgentJobRuns do
  use Ecto.Migration

  def change do
    # Table may already exist with: id, agent_uuid, build_id, result, inserted_at, updated_at
    create_if_not_exists table(:agent_job_runs) do
      add :agent_uuid, :string, null: false
      add :build_id, :string, null: false
      add :pipeline_name, :string, null: false
      add :pipeline_counter, :integer, default: 1
      add :stage_name, :string, null: false
      add :stage_counter, :integer, default: 1
      add :job_name, :string, null: false
      add :result, :string
      add :state, :string, default: "Scheduled"

      timestamps(type: :utc_datetime)
    end

    # Add columns that may be missing on an existing table (created earlier with fewer columns)
    for {col, type, default} <- [
          {"pipeline_name", "varchar(255)", "'unknown'"},
          {"pipeline_counter", "integer", "1"},
          {"stage_name", "varchar(255)", "'unknown'"},
          {"stage_counter", "integer", "1"},
          {"job_name", "varchar(255)", "'unknown'"},
          {"state", "varchar(255)", "'Scheduled'"}
        ] do
      execute(
        "ALTER TABLE agent_job_runs ADD COLUMN IF NOT EXISTS #{col} #{type} DEFAULT #{default}",
        ""
      )
    end

    create_if_not_exists index(:agent_job_runs, [:agent_uuid])
    create_if_not_exists unique_index(:agent_job_runs, [:agent_uuid, :build_id])
  end
end
