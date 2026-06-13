defmodule ExGoCD.Repo.Migrations.AddPauseFieldsToPipelines do
  use Ecto.Migration

  def change do
    alter table(:pipelines) do
      add :paused, :boolean, default: false, null: false
      add :paused_by, :string
      add :pause_cause, :string
      add :paused_at, :utc_datetime
    end
  end
end

