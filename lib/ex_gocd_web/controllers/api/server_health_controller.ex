defmodule ExGoCDWeb.API.ServerHealthController do
  @moduledoc """
  GoCD Server Health Messages API (api-server-health-messages-v1).
  Returns global server health status — errors, warnings, and disk space.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.MaintenanceMode

  @doc "GET /api/server_health_messages"
  def show(conn, _params) do
    disk_status = ExGoCD.Monitors.DiskSpace.status()
    maintenance = MaintenanceMode.enabled?()

    messages =
      cond do
        maintenance ->
          [
            %{
              level: "WARNING",
              message: "Server is in maintenance mode. Pipeline scheduling is paused."
            }
          ]

        disk_status == :critical ->
          [
            %{
              level: "ERROR",
              message: "Disk space is critically low. Pipeline scheduling has been paused."
            }
          ]

        # The guard is blind: say so rather than report a healthy disk. Nothing
        # blocks on this — see `ExGoCD.SchedulingChecker.DiskSpace`.
        disk_status == :unknown ->
          [
            %{
              level: "WARNING",
              message:
                "Disk space could not be determined: the artifact directory could not be read."
            }
          ]

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
end
