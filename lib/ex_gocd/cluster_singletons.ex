defmodule ExGoCD.ClusterSingletons do
  @moduledoc """
  Starts the cluster's singleton processes under the Horde supervisor, and starts
  them again if that supervisor is replaced.

  These processes — the scheduler, the pollers, the elastic schedulers, the ones
  that must exist once per cluster — cannot be children of the application
  supervisor: each node starts the same tree, and Horde is what makes a singleton
  single. So they are started by name from here.

  That starting used to happen in a `Task` that ran once at boot, which meant a
  Horde supervisor restart left the cluster with no scheduler until the node
  restarted. It is not hypothetical: a poller cashing out took the supervisor with
  it, every agent ping answered `500 no process: ExGoCD.Scheduler`, and the only
  way back was a restart. This process watches the supervisor instead.
  """
  use GenServer
  require Logger

  @singletons [
    ExGoCD.MaintenanceMode,
    ExGoCD.Analytics.SnapshotCollector,
    ExGoCD.Scheduler,
    ExGoCD.AgentRegistry,
    ExGoCD.Materials.Poller,
    ExGoCD.Materials.TimerScheduler,
    ExGoCD.Pipelines.ConsoleActivityMonitor,
    ExGoCD.SchedulingChecker.TriggerMonitor,
    ExGoCD.Monitors.DiskSpace,
    ExGoCD.ElasticAgentScheduler,
    ExGoCD.DockerElasticAgentScheduler,
    ExGoCD.ConfigRepos.Poller,
    ExGoCD.Backup,
    ExGoCD.StartupReaper
  ]

  @doc """
  Starts the starter.

  Options: `:supervisor` (name, default `ExGoCD.HordeSupervisor`), `:children`
  (the child modules, default the cluster's singletons), `:retry` (milliseconds
  between attempts to find the supervisor), `:name`.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The modules this starts, in order."
  def singletons, do: @singletons

  @impl true
  def init(opts) do
    state = %{
      supervisor: Keyword.get(opts, :supervisor, ExGoCD.HordeSupervisor),
      children: Keyword.get(opts, :children, @singletons),
      retry: Keyword.get(opts, :retry, 100),
      watching: nil
    }

    {:ok, ensure_started(state)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{watching: ref} = state) do
    {:noreply, ensure_started(%{state | watching: nil})}
  end

  def handle_info(:retry, state), do: {:noreply, ensure_started(state)}
  def handle_info(_message, state), do: {:noreply, state}

  # The supervisor may not be up yet when this starts, and it may be coming back
  # when it went down: either way, ask again shortly.
  defp ensure_started(state) do
    case Process.whereis(state.supervisor) do
      nil ->
        Process.send_after(self(), :retry, state.retry)
        state

      pid ->
        start_children(state)
        %{state | watching: Process.monitor(pid)}
    end
  end

  defp start_children(state) do
    Enum.each(state.children, fn child ->
      # Horde's own start_child normalises the shorthand into the map its
      # implementation needs; the stdlib one converts it into OTP's tuple form,
      # which Horde's implementation then rejects.
      case Horde.DynamicSupervisor.start_child(state.supervisor, {child, []}) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        # A child whose start_link answers :ignore has switched itself off here.
        :ignore -> :ok
        {:error, reason} -> Logger.error("Could not start #{inspect(child)}: #{inspect(reason)}")
      end
    end)
  end
end
