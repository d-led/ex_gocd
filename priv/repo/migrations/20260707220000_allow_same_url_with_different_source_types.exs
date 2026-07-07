defmodule ExGoCD.Repo.Migrations.AllowSameUrlWithDifferentSourceTypes do
  use Ecto.Migration

  def up do
    drop_if_exists(unique_index(:config_repos, [:url]))
    create unique_index(:config_repos, [:url, :source_type])
  end

  def down do
    drop_if_exists(unique_index(:config_repos, [:url, :source_type]))
    create unique_index(:config_repos, [:url])
  end
end
