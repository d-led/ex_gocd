defmodule ExGoCDWeb.API.Admin.BackupConfigController do
  @moduledoc """
  Backup configuration API.
  GoCD parity: GET/POST/DELETE /go/api/config/backup.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.{Repo, BackupConfig}

  @doc "GET /api/admin/config/backup"
  def show(conn, _params) do
    config = Repo.one(BackupConfig) || %BackupConfig{}
    json(conn, backup_config_json(config))
  end

  @doc "POST /api/admin/config/backup"
  def create(conn, params) do
    existing = Repo.one(BackupConfig)

    result =
      if existing do
        existing |> BackupConfig.changeset(params) |> Repo.update()
      else
        %BackupConfig{} |> BackupConfig.changeset(params) |> Repo.insert()
      end

    case result do
      {:ok, config} ->
        conn |> put_status(:created) |> json(backup_config_json(config))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: error_map(changeset)})
    end
  end

  @doc "DELETE /api/admin/config/backup"
  def delete(conn, _params) do
    case Repo.one(BackupConfig) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "No backup config"})

      config ->
        Repo.delete(config)
        json(conn, %{message: "Backup config deleted"})
    end
  end

  defp backup_config_json(c) do
    %{
      schedule: c.schedule,
      retention_days: c.retention_days,
      backup_dir: c.backup_dir,
      post_backup_script: c.post_backup_script,
      enabled: c.enabled,
      last_backup_at: c.last_backup_at,
      last_backup_status: c.last_backup_status
    }
  end

  defp error_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
