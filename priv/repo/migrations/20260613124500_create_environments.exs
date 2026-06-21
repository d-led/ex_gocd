defmodule ExGoCD.Repo.Migrations.CreateEnvironments do
  use Ecto.Migration

  def change do
    create table(:environments) do
      add :name, :string, null: false
      add :environment_variables, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:environments, [:name])

    create table(:environment_pipelines) do
      add :environment_id, references(:environments, on_delete: :delete_all), null: false
      add :pipeline_id, references(:pipelines, on_delete: :delete_all), null: false
    end

    create index(:environment_pipelines, [:environment_id])
    create unique_index(:environment_pipelines, [:pipeline_id])
  end
end
