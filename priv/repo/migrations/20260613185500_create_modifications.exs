defmodule ExGoCD.Repo.Migrations.CreateModifications do
  use Ecto.Migration

  def change do
    create table(:modifications) do
      add :material_id, references(:materials, on_delete: :delete_all), null: false
      add :revision, :string, null: false
      add :committer_name, :string
      add :committer_email, :string
      add :comment, :text
      add :modified_time, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:modifications, [:material_id])
    create unique_index(:modifications, [:material_id, :revision])
  end
end
