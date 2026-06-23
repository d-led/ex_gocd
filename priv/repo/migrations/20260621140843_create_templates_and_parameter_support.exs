defmodule ExGoCD.Repo.Migrations.CreateTemplatesAndParameterSupport do
  use Ecto.Migration

  def change do
    create table(:templates) do
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:templates, [:name])

    alter table(:stages) do
      modify :pipeline_id, :integer, null: true
      add :template_id, references(:templates, on_delete: :delete_all)
    end

    alter table(:pipelines) do
      add :template_id, references(:templates, on_delete: :nilify_all)
      add :parameters, :map, default: %{}
    end
  end
end
