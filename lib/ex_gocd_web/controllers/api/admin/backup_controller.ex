defmodule ExGoCDWeb.API.Admin.BackupController do
  use ExGoCDWeb, :controller

  require Logger

  @doc "POST /api/admin/backups — triggers a database backup"
  def create(conn, _params) do
    result = ExGoCD.Backup.create()

    case result do
      :ok ->
        json(conn, %{message: "Backup initiated."})

      {:error, :already_running} ->
        conn |> put_status(:conflict) |> json(%{error: "A backup is already in progress."})
    end
  end

  @doc "GET /api/admin/backups/:id — returns backup status"
  def show(conn, _params) do
    status = ExGoCD.Backup.status()
    json(conn, status)
  end
end
