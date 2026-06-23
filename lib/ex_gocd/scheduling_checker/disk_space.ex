defmodule ExGoCD.SchedulingChecker.DiskSpace do
  @moduledoc """
  Blocks pipeline scheduling when disk space on the artifact directory
  falls below the critical threshold.

  Mirrors GoCD's `OutOfDiskSpaceChecker`. Delegates to the running
  `ExGoCD.Monitors.DiskSpace` GenServer for current status.

  If the DiskSpace monitor is not running (e.g., in tests), it defaults
  to `:ok` — disk is assumed to have sufficient space.
  """
  use ExGoCD.SchedulingChecker

  @impl true
  def check(_pipeline_name) do
    try do
      case ExGoCD.Monitors.DiskSpace.status() do
        :critical -> {:error, :disk_space_critical}
        _ -> :ok
      end
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end
end
