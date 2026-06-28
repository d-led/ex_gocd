defmodule ExGoCD.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:roles) do
      add :name, :string, null: false
      add :type, :string, default: "gocd"
      add :users, {:array, :string}, default: []
      add :auth_config_id, :string
      add :properties, :map, default: %{}
      add :policy, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:roles, [:name])
  end
end
