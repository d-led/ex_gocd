defmodule ExGoCDWeb.API.Admin.BackupController do
  use ExGoCDWeb, :controller

  require Logger

  @doc "POST /api/admin/backups — triggers a database backup"
  def create(conn, _params) do
    # Async backup via Task
    Task.start(fn ->
      timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
      backup_dir = System.get_env("BACKUP_DIR") || "backups"
      File.mkdir_p!(backup_dir)
      backup_path = Path.join(backup_dir, "ex_gocd_backup_#{timestamp}.dump")

      case System.cmd("pg_dump", [
        "-Fc",
        "-f", backup_path,
        "-h", db_host(),
        "-U", db_user(),
        db_name()
      ], env: [{"PGPASSWORD", db_password()}], stderr_to_stdout: true) do
        {_, 0} ->
          Logger.info("Backup created: #{backup_path}")

        {output, code} ->
          Logger.error("Backup failed (code #{code}): #{output}")
      end
    end)

    json(conn, %{message: "Backup initiated."})
  end

  defp db_host, do: Application.get_env(:ex_gocd, ExGoCD.Repo)[:hostname] || "localhost"
  defp db_user, do: Application.get_env(:ex_gocd, ExGoCD.Repo)[:username] || "postgres"
  defp db_password, do: Application.get_env(:ex_gocd, ExGoCD.Repo)[:password] || ""
  defp db_name, do: Application.get_env(:ex_gocd, ExGoCD.Repo)[:database] || "ex_gocd_dev"
end
