defmodule ExGoCD.ClusterInfoServer do
  @moduledoc """
  Polls cluster state every 3 seconds and broadcasts via local PubSub.
  Pattern copied from ssr-robust-live-svg.
  """
  use GenServer

  @topic "cluster:info"
  @interval_ms 3_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current cluster info snapshot.
  Called by LiveViews in mount to get initial data without waiting for a tick.
  """
  def get_cluster_info do
    GenServer.call(__MODULE__, :get_cluster_info)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{known_nodes: []}}
  end

  @impl true
  def handle_call(:get_cluster_info, _from, state) do
    {:reply, collect_cluster_info(), state}
  end

  @impl true
  def handle_info(:tick, state) do
    info = collect_cluster_info()

    # Detect node joins/leaves
    current = info.nodes
    previous = state.known_nodes
    joined = current -- previous
    left = previous -- current

    Enum.each(joined, fn node ->
      ExGoCD.ClusterEventLog.record(:node_joined, %{node: node})
    end)

    Enum.each(left, fn node ->
      ExGoCD.ClusterEventLog.record(:node_left, %{node: node})
    end)

    Phoenix.PubSub.local_broadcast(ExGoCD.PubSub, @topic, {:cluster_info, info})
    schedule_tick()
    {:noreply, %{state | known_nodes: current}}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @interval_ms)

  defp collect_cluster_info do
    other_nodes = Node.list() |> Enum.map(&to_string/1) |> Enum.sort()
    node_self = to_string(Node.self())
    singletons = singleton_locations()

    %{
      self: node_self,
      nodes: [node_self | other_nodes],
      singletons: singletons
    }
  end

  defp singleton_locations do
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
