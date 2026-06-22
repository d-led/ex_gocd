defmodule ExGoCD.Repo.Migrations.AddSecureVariables do
  use Ecto.Migration

  def change do
    alter table(:pipelines) do
      add :secure_variables, :map, default: %{}, null: false
    end

    alter table(:stages) do
      add :secure_variables, :map, default: %{}, null: false
    end

    alter table(:jobs) do
      add :secure_variables, :map, default: %{}, null: false
    end
  end
end
