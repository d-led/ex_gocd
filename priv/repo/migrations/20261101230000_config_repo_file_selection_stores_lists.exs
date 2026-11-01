defmodule ExGoCD.Repo.Migrations.ConfigRepoFileSelectionStoresLists do
  use Ecto.Migration

  # A selection is a list of job names and a list of trigger names. Both columns
  # were jsonb, which holds an object, so every insert of a list was rejected
  # before it reached the database and no row ever held a value. The columns are
  # dropped rather than converted for that reason: there is nothing in them.
  def up do
    alter table(:config_repo_file_selections) do
      remove :selected_jobs
      remove :selected_triggers
    end

    alter table(:config_repo_file_selections) do
      add :selected_jobs, {:array, :string}, default: [], null: false
      add :selected_triggers, {:array, :string}, default: [], null: false
    end
  end

  def down do
    alter table(:config_repo_file_selections) do
      remove :selected_jobs
      remove :selected_triggers
    end

    alter table(:config_repo_file_selections) do
      add :selected_jobs, :map
      add :selected_triggers, :map
    end
  end
end
