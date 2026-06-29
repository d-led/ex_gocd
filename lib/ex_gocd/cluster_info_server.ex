defmodule ExGoCD.ClusterInfoServer do
  @moduledoc """
  Tracks this node's singleton locations via Phoenix Presence every 3s.
  Presence handles joins/leaves/crashes — no manual cleanup needed.
  AdminLive subscribes to "cluster:presence" for stable, sorted updates.
  """
  use GenServer

  @topic "cluster:presence"
  @interval_ms 3_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    track_presence()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @interval_ms)

  # -- Presence tracking --

  defp track_presence do
    node_str = to_string(Node.self())
    singletons = singleton_locations()

    ExGoCD.ClusterPresence.track(
      self(),
      @topic,
      node_str,
      %{singletons: singletons, tracked_at: System.system_time(:second)}
    )
  end

  defp singleton_locations do
    registry = ExGoCD.HordeRegistry

    singleton_modules()
    |> Enum.map(fn mod ->
      node =
        case Horde.Registry.lookup(registry, mod) do
          [{pid, _}] -> to_string(node(pid))
          [] -> :not_found
        end

      {mod, node}
    end)
    |> Enum.into(%{})
  end

  defp singleton_modules do
    [
      ExGoCD.Scheduler,
      ExGoCD.ElasticAgentScheduler,
      ExGoCD.Analytics.SnapshotCollector,
      ExGoCD.Materials.Poller,
      ExGoCD.Pipelines.ConsoleActivityMonitor,
      ExGoCD.MaintenanceMode,
      ExGoCD.Backup,
      ExGoCD.Monitors.DiskSpace,
      ExGoCD.AgentRegistry,
      ExGoCD.SchedulingChecker.TriggerMonitor
    ]
  end
end
