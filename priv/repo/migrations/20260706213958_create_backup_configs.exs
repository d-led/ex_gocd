defmodule ExGoCD.Repo.Migrations.CreateBackupConfigs do
  use Ecto.Migration

  def change do
    create table(:backup_configs) do
      add :schedule, :string
      add :retention_days, :integer, default: 7
      add :backup_dir, :string
      add :post_backup_script, :string
      add :enabled, :boolean, default: true
      add :last_backup_at, :utc_datetime
      add :last_backup_status, :string
      timestamps()
    end
  end
end
