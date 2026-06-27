defmodule ExGoCD.Repo.Migrations.CreateNotificationFilters do
  use Ecto.Migration

  def change do
    create table(:notification_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :id, on_delete: :delete_all), null: false
      add :pipeline_name, :string, null: false
      add :stage_name, :string, null: false
      add :event, :string, null: false
      add :match_committer, :boolean, default: false

      timestamps()
    end

    create index(:notification_filters, [:user_id])
  end
end
