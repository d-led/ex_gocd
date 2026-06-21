defmodule ExGoCD.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs) do
      add :actor, :string, null: false
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_name, :string
      add :details, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:audit_logs, [:action])
    create index(:audit_logs, [:resource_type, :resource_name])
    create index(:audit_logs, [:inserted_at])
  end
end
