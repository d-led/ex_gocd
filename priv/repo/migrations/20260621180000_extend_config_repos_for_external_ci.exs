defmodule ExGoCD.Repo.Migrations.ExtendConfigReposForExternalCi do
  use Ecto.Migration

  def change do
    # 0.1 Extend config_repos
    alter table(:config_repos) do
      add :source_type, :string, default: "gocd_pipeline", null: false
      add :plugin_id, :string
      add :configuration, :map, default: %{}
    end

    create index(:config_repos, [:source_type])

    # 0.2 config_repo_files
    create table(:config_repo_files) do
      add :config_repo_id, references(:config_repos, on_delete: :delete_all), null: false
      add :path, :string, null: false
      add :source_type, :string, null: false
      add :checksum, :string
      add :last_seen_at, :utc_datetime
      add :status, :string, default: "new", null: false
      add :raw_content, :text
      add :parsed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:config_repo_files, [:config_repo_id, :path])
    create index(:config_repo_files, [:status])

    # 0.3 config_repo_file_selections
    create table(:config_repo_file_selections) do
      add :config_repo_file_id, references(:config_repo_files, on_delete: :delete_all), null: false
      add :mode, :string, default: "translate", null: false
      add :selected_jobs, :map
      add :selected_triggers, :map
      add :overrides, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:config_repo_file_selections, [:config_repo_file_id])

    # 0.4 Add config_repo_id to pipelines
    alter table(:pipelines) do
      add :config_repo_id, references(:config_repos, on_delete: :nilify_all)
      add :source_file_path, :string
    end

    create index(:pipelines, [:config_repo_id])

    # 0.5 Extend tasks
    alter table(:tasks) do
      add :external_config, :map, default: %{}
    end

    # 0.6 Add capabilities to agents
    alter table(:agents) do
      add :capabilities, {:array, :string}, default: []
    end
  end
end
