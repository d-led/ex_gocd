defmodule ExGoCDWeb.API.Admin.MaintenanceModeController do
  use ExGoCDWeb, :controller

  alias ExGoCD.MaintenanceMode

  @doc "GET /api/admin/maintenance_mode/info"
  def show(conn, _params) do
    json(conn, MaintenanceMode.info())
  end

  @doc "POST /api/admin/maintenance_mode/enable"
  def enable(conn, _params) do
    case MaintenanceMode.enable() do
      {:ok, _} -> json(conn, %{message: "Maintenance mode enabled."})
      {:error, reason} -> conn |> put_status(:conflict) |> json(%{message: "Already #{reason}"})
    end
  end

  @doc "POST /api/admin/maintenance_mode/disable"
  def disable(conn, _params) do
    case MaintenanceMode.disable() do
      {:ok, _} -> json(conn, %{message: "Maintenance mode disabled."})
      {:error, reason} -> conn |> put_status(:conflict) |> json(%{message: "Already #{reason}"})
    end
  end
end
