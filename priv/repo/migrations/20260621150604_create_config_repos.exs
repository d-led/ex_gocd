defmodule ExGoCD.Repo.Migrations.CreateConfigRepos do
  use Ecto.Migration

  def change do
    create table(:config_repos) do
      add :url, :string, null: false
      add :branch, :string, default: "main"
      add :material_type, :string, default: "git"
      add :last_parsed_at, :utc_datetime
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:config_repos, [:url])
  end
end
