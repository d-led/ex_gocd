defmodule ExGoCD.Repo.Migrations.CreateServerConfig do
  @moduledoc """
  The server's own settings, the ones GoCD keeps in `<server>` of
  `cruise-config.xml`: the site URLs it links to, the default job timeout, and
  the artifact directory with its purge settings.

  Until now they came from the environment only, so the documented write API had
  nothing to write to. The table holds one row — the check constraint says so —
  and a setting the row leaves null falls back to the environment.
  """
  use Ecto.Migration

  def change do
    create table(:server_configs, primary_key: false) do
      add :id, :bigint, primary_key: true, default: 1
      add :site_url, :text
      add :secure_site_url, :text
      add :default_job_timeout, :text
      add :artifacts_dir, :text
      add :purge_start_disk_space, :float
      add :purge_upto_disk_space, :float

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:server_configs, :server_configs_is_one_row, check: "id = 1")
  end
end
