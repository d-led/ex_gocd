defmodule ExGoCD.Repo.Migrations.AddTimerOnlyOnChangesToPipelines do
  use Ecto.Migration

  def change do
    alter table(:pipelines) do
      add :timer_only_on_changes, :boolean, default: false, null: false
    end
  end
end
