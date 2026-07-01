defmodule ExGoCD.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Allow running tests without Postgres (e.g. CI or converter-only tests)
    skip_db? = System.get_env("EX_GOCD_TEST_NO_DB") == "1"

    # Attach JSON log backend for Fluent Bit → Loki (dev only, fails gracefully)
    if Application.get_env(:logger, ExGoCD.LoggerJSON) do
      LoggerBackends.add(ExGoCD.LoggerJSON)
    end

    # Initialize OpenTelemetry unless disabled
    unless System.get_env("EX_GOCD_NO_OTEL") == "1" do
      ExGoCD.Otel.setup()
      # Attach crash telemetry: Phoenix exceptions → OTel span events
      ExGoCD.CrashTelemetry.attach()
    end

    # ETS table for cross-process trace context propagation (assign → agent report)
    ExGoCD.VsmContextStore.setup()

    # ── Cluster infrastructure ────────────────────────────────────────
    topologies = cluster_topologies()

    cluster_children = [
      {Cluster.Supervisor, [topologies, [name: ExGoCD.ClusterSupervisor]]},
      {Horde.Registry, [name: ExGoCD.HordeRegistry, keys: :unique, members: :auto]},
      {Horde.DynamicSupervisor,
       [
         name: ExGoCD.HordeSupervisor,
         strategy: :one_for_one,
         restart: :transient,
         distribution_strategy: Horde.UniformDistribution,
         process_redistribution: :passive,
         members: :auto,
         max_restarts: 90,
         max_seconds: 30
       ]},
      Supervisor.child_spec(
        {Task,
         fn ->
           for mod <- [
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
                 ExGoCD.Backup
               ] do
             Horde.DynamicSupervisor.start_child(ExGoCD.HordeSupervisor, {mod, []})
           end

           :ok
         end},
        id: :horde_singletons_starter
      ),
      ExGoCD.ClusterInfoServer
    ]

    base =
      [
        ExGoCDWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:ex_gocd, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: ExGoCD.PubSub},
        ExGoCD.ClusterPresence,
        ExGoCDWeb.AgentPresence,
        ExGoCD.Plugin.Registry,
        ExGoCD.ClusterEventLog,
        ExGoCD.ConfigRepos.Poller,
        ExGoCD.TestAgentSupervisor,
        # Per-node artifact cleanup (must run on every node with a disk cache,
        # NOT as a Horde singleton — each node has its own artifact storage)
        ExGoCD.ArtifactCleanup,
        ExGoCDWeb.Endpoint
      ] ++ cluster_children

    children =
      if skip_db? do
        base
      else
        [ExGoCDWeb.Telemetry, ExGoCD.Repo | Enum.drop(base, 1)]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExGoCD.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Clean up stale LostContact agents on startup (accumulate on DB resets)
    unless skip_db? do
      Task.start(fn ->
        Process.sleep(2000)
        cleaned = ExGoCD.Agents.cleanup_stale_lost_contact()
        if cleaned > 0, do: Logger.info("Cleaned up #{cleaned} stale LostContact agents")
        test_cleaned = ExGoCD.Agents.clean_test_agents()
        if test_cleaned > 0, do: Logger.info("Cleaned up #{test_cleaned} orphaned test agents")
      end)
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExGoCDWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp cluster_topologies do
    case System.get_env("ERLANG_SEED_NODES", "")
         |> String.split(",", trim: true)
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == ""))
         |> Enum.map(&String.to_atom/1) do
      [] -> [default: [strategy: Cluster.Strategy.Gossip]]
      seeds -> [default: [strategy: Cluster.Strategy.Epmd, config: [hosts: seeds]]]
    end
  end
end
