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

    base = [
      ExGoCDWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ex_gocd, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExGoCD.PubSub},
      ExGoCDWeb.AgentPresence,
      ExGoCD.Scheduler,
      ExGoCD.AgentRegistry,
      ExGoCD.TestAgentSupervisor,
      ExGoCDWeb.Endpoint,
      ExGoCD.Materials.Poller,
      ExGoCD.Materials.TimerScheduler,
      ExGoCD.Pipelines.ConsoleActivityMonitor,
      ExGoCD.MaintenanceMode,
      ExGoCD.SchedulingChecker.TriggerMonitor,
      ExGoCD.Monitors.DiskSpace,
      ExGoCD.ElasticAgentScheduler
    ]

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
end
