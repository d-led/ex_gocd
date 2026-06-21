defmodule ExGoCD.Repo.Migrations.CreatePipelineGroupPermissions do
  use Ecto.Migration

  def change do
    create table(:pipeline_group_permissions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :pipeline_group, :string, null: false
      add :role, :string, null: false, default: "viewer"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pipeline_group_permissions, [:user_id, :pipeline_group])
  end
end
