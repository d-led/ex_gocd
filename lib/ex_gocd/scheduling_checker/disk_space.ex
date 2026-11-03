defmodule ExGoCD.SchedulingChecker.DiskSpace do
  @moduledoc """
  Blocks pipeline scheduling when disk space on the artifact directory
  falls below the critical threshold.

  Mirrors GoCD's `OutOfDiskSpaceChecker`. It asks the running
  `ExGoCD.Monitors.DiskSpace` for the last measurement.

  A disk the monitor could not measure (`:unknown`) does not block scheduling:
  a guard that cannot see is not evidence that the disk is full, and the server
  health API reports the blind spot instead.
  """
  use ExGoCD.SchedulingChecker

  @impl true
  def check(_pipeline_name) do
    case ExGoCD.Monitors.DiskSpace.status() do
      :critical -> {:error, :disk_space_critical}
      _other -> :ok
    end
  end
end
