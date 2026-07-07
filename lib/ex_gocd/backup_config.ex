defmodule ExGoCD.BackupConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "backup_configs" do
    field :schedule, :string
    field :retention_days, :integer, default: 7
    field :backup_dir, :string
    field :post_backup_script, :string
    field :enabled, :boolean, default: true
    field :last_backup_at, :utc_datetime
    field :last_backup_status, :string

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(
      attrs,
      ~w(schedule retention_days backup_dir post_backup_script enabled last_backup_at last_backup_status)a
    )
    |> validate_number(:retention_days, greater_than: 0)
  end
end
