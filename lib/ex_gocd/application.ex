defmodule ExGoCD.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

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
      ExGoCD.MaintenanceMode
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
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExGoCDWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
