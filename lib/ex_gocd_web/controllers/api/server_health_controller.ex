defmodule ExGoCDWeb.API.ServerHealthController do
  @moduledoc """
  GoCD Server Health Messages API (api-server-health-messages-v1).
  Returns global server health status — errors, warnings, and disk space.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.MaintenanceMode

  @doc "GET /api/server_health_messages"
  def show(conn, _params) do
    disk_status = disk_health()
    maintenance = MaintenanceMode.enabled?()

    messages =
      cond do
        maintenance ->
          [%{level: "WARNING", message: "Server is in maintenance mode. Pipeline scheduling is paused."}]

        disk_status == :critical ->
          [%{level: "ERROR", message: "Disk space is critically low. Pipeline scheduling has been paused."}]

        disk_status == :warning ->
          [%{level: "WARNING", message: "Disk space is low."}]

        true ->
          []
      end

    conn
    |> put_status(:ok)
    |> json(%{health: health_status(messages), messages: messages})
  end

  defp health_status([]), do: "OK"
  defp health_status(messages) do
    if Enum.any?(messages, &(&1.level == "ERROR")), do: "ERROR", else: "WARNING"
  end

  defp disk_health do
    try do
      ExGoCD.Monitors.DiskSpace.status()
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end
end
