defmodule ExGoCDWeb.API.Admin.MaintenanceModeController do
  use ExGoCDWeb, :controller

  import Ecto.Query

  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.MaintenanceMode
  alias ExGoCD.Repo

  @doc "GET /api/admin/maintenance_mode/info"
  def show(conn, _params) do
    json(conn, present(MaintenanceMode.info(), running_systems()))
  end

  # GoCD toggles maintenance mode with GET as well as the POST we started with.
  @doc "GET or POST /api/admin/maintenance_mode/enable"
  def enable(conn, _params) do
    case MaintenanceMode.enable() do
      {:ok, _} -> json(conn, %{message: "Maintenance mode enabled."})
      {:error, reason} -> conn |> put_status(:conflict) |> json(%{message: "Already #{reason}"})
    end
  end

  @doc "GET or POST /api/admin/maintenance_mode/disable"
  def disable(conn, _params) do
    case MaintenanceMode.disable() do
      {:ok, _} -> json(conn, %{message: "Maintenance mode disabled."})
      {:error, reason} -> conn |> put_status(:conflict) |> json(%{message: "Already #{reason}"})
    end
  end

  # GoCD nests the answer under `_embedded` and names the flag
  # `is_maintenance_mode`; `attributes` is the list of work that keeps a server
  # from entering maintenance mode. We track jobs, not material updates, so that
  # list is reported empty rather than guessed at.
  defp present(state, systems) do
    %{
      _links: %{
        self: %{href: "/api/admin/maintenance_mode/info"},
        doc: %{href: "https://api.gocd.org/current/#maintenance-mode-info"}
      },
      _embedded: %{
        is_maintenance_mode: state.enabled,
        metadata: %{updated_by: state.enabled_by, updated_on: state.enabled_at},
        attributes: %{
          has_running_systems: systems.running_jobs != [] or systems.scheduled_jobs != [],
          running_systems: systems
        }
      }
    }
  end

  # A run is over once the agent reports it completed; anything else is still
  # something the server has to wait for.
  defp running_systems do
    runs =
      Repo.all(
        from(r in AgentJobRun, where: r.state != "Completed", select: {r.state, r.build_id})
      )

    %{
      material_update_in_progress: [],
      scheduled_jobs: for({"Scheduled", build_id} <- runs, do: build_id),
      running_jobs: for({state, build_id} <- runs, state != "Scheduled", do: build_id)
    }
  end
end
