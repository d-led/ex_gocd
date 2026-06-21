defmodule ExGoCD.Repo.Migrations.FixAuditLogsUpdatedAtNullable do
  use Ecto.Migration

  def change do
    # For an append-only audit log, updated_at is never set by Ecto
    # (schema uses `timestamps(updated_at: false)`).
    # Make the column nullable so inserts don't fail with not-null violation.
    execute(
      "ALTER TABLE audit_logs ALTER COLUMN updated_at DROP NOT NULL",
      "ALTER TABLE audit_logs ALTER COLUMN updated_at SET NOT NULL"
    )
  end
end
