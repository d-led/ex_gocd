defmodule ExGoCD.Repo.Migrations.CreatePipelineMaterialRevisions do
  use Ecto.Migration

  def change do
    create table(:pipeline_material_revisions) do
      add :pipeline_instance_id, references(:pipeline_instances, on_delete: :delete_all),
        null: false

      add :material_id, references(:materials, on_delete: :delete_all), null: false
      add :modification_id, references(:modifications, on_delete: :nilify_all)
      add :parent_pipeline_instance_id, references(:pipeline_instances, on_delete: :nilify_all)
      add :revision, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pipeline_material_revisions, [:pipeline_instance_id])
    create index(:pipeline_material_revisions, [:material_id])
    create unique_index(:pipeline_material_revisions, [:pipeline_instance_id, :material_id])
  end
end
