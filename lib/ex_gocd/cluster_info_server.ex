defmodule ExGoCD.ClusterInfoServer do
  @moduledoc """
  Polls cluster state every 3 seconds and broadcasts via PubSub.
  """
  use GenServer

  @topic "cluster:info"
  @interval_ms 3_000

  # -- Public API --

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    info = collect_cluster_info()
    Phoenix.PubSub.broadcast(ExGoCD.PubSub, @topic, {:cluster_info, info})
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @interval_ms)

  # -- Info collection --

  defp collect_cluster_info do
    nodes = Node.list() |> Enum.map(&to_string/1)
    singleton_locations = singleton_process_locations()
    node_self = to_string(Node.self())

    %{
      self: node_self,
      nodes: [node_self | nodes],
      singletons: singleton_locations
    }
  end

  def singleton_process_locations do
    registry = ExGoCD.HordeRegistry

    singleton_modules()
    |> Enum.map(fn mod ->
      {mod, lookup_singleton(registry, mod)}
    end)
    |> Enum.into(%{})
  end

  defp lookup_singleton(registry, mod) do
    case Horde.Registry.lookup(registry, mod) do
      [{pid, _}] -> to_string(node(pid))
      [] -> :not_found
    end
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
