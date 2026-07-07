defmodule ExGoCDWeb.BackupController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Backup

  @doc """
  POST /go/api/backups — triggers a new backup.
  Returns 202 with backup status on success, 409 if already running.
  """
  def create(conn, _params) do
    case Backup.create() do
      :ok ->
        status = Backup.status()

        conn
        |> put_status(:accepted)
        |> json(%{message: status.message})

      {:error, :already_running} ->
        conn
        |> put_status(:conflict)
        |> json(%{message: "Backup already in progress"})
    end
  end

  @doc """
  GET /go/api/backups/:id — returns the current backup status.
  The :id param is currently ignored (single-backup model).
  """
  def show(conn, _params) do
    status = Backup.status()
    json(conn, status)
  end
end
