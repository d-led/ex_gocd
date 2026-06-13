defmodule ExGoCD.Repo.Migrations.AddLockedToPipelines do
  use Ecto.Migration

  def change do
    alter table(:pipelines) do
      add :locked, :boolean, default: false, null: false
    end
  end
end
