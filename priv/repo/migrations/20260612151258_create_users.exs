defmodule ExGoCD.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string, null: false
      add :display_name, :string, null: false
      add :roles, {:array, :string}, null: false, default: []
      add :status, :string, null: false, default: "Active"

      timestamps()
    end

    create unique_index(:users, [:username])
  end
end
