defmodule ExGoCD.Repo.Migrations.AddRemoteIpToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add :remote_ip, :string
    end
  end
end
