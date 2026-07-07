defmodule ExGoCDWeb.BackupConfigController do
  use ExGoCDWeb, :controller

  alias ExGoCD.{BackupConfig, Repo}

  @doc """
  GET /go/api/config/backup — returns the current backup configuration.
  """
  def show(conn, _params) do
    config = Repo.one(BackupConfig) || %BackupConfig{}

    json(conn, %{
      schedule: config.schedule,
      retention_days: config.retention_days,
      backup_dir: config.backup_dir,
      post_backup_script: config.post_backup_script,
      enabled: config.enabled,
      last_backup_at: config.last_backup_at,
      last_backup_status: config.last_backup_status
    })
  end

  @doc """
  POST /go/api/config/backup — creates or updates the backup configuration.
  """
  def create(conn, params) do
    existing = Repo.one(BackupConfig)

    changeset =
      case existing do
        nil -> BackupConfig.changeset(%BackupConfig{}, params)
        config -> BackupConfig.changeset(config, params)
      end

    case Repo.insert_or_update(changeset) do
      {:ok, config} ->
        json(conn, %{
          schedule: config.schedule,
          retention_days: config.retention_days,
          backup_dir: config.backup_dir,
          post_backup_script: config.post_backup_script,
          enabled: config.enabled
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  @doc """
  DELETE /go/api/config/backup — deletes the backup configuration.
  """
  def delete(conn, _params) do
    case Repo.one(BackupConfig) do
      nil ->
        json(conn, %{message: "No backup config to delete"})

      config ->
        Repo.delete!(config)
        json(conn, %{message: "Backup config deleted"})
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
