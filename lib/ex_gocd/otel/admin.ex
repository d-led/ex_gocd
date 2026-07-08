defmodule ExGoCD.Otel.Admin do
  @moduledoc """
  Read-only OpenTelemetry status queries for the admin dashboard.

  Provides a snapshot of the current OTel configuration, SDK state,
  and collector reachability — without side effects.
  """

  @doc """
  Returns a map of the current OpenTelemetry status.
  """
  def status do
    %{
      sdk_enabled: sdk_enabled?(),
      sdk_disabled: sdk_disabled?(),
      exporter: exporter(),
      otlp_endpoint: otlp_endpoint(),
      service_name: service_name(),
      env_vars: env_vars(),
      instrumentation: instrumentation(),
      collector_reachable: collector_reachable?(),
      no_otel_env: System.get_env("EX_GOCD_NO_OTEL") == "1",
      config_source: config_source()
    }
  end

  # ── SDK state ──────────────────────────────────────────────────────

  defp sdk_enabled? do
    not sdk_disabled?()
  end

  defp sdk_disabled? do
    # Check both the raw SDK config AND our app-level toggle
    Application.get_env(:opentelemetry, :sdk_disabled, false) or
      app_exporter() == :none
  end

  # ── App-level config ───────────────────────────────────────────────

  defp app_config do
    Application.get_env(:ex_gocd, :otel, [])
  end

  defp app_exporter do
    Keyword.get(app_config(), :exporter, :none)
  end

  defp exporter do
    case app_exporter() do
      :otlp -> :otlp
      :none -> :none
      other -> other
    end
  end

  defp otlp_endpoint do
    Keyword.get(app_config(), :otlp_endpoint) ||
      Application.get_env(:opentelemetry_exporter, :otlp_endpoint) ||
      "not configured"
  end

  defp service_name do
    Keyword.get(app_config(), :service_name, "ex_gocd")
  end

  # ── Config source (why is OTel in this state?) ────────────────────

  defp config_source do
    env = Application.get_env(:ex_gocd, :env, :prod)

    cond do
      System.get_env("EX_GOCD_NO_OTEL") == "1" ->
        "EX_GOCD_NO_OTEL=1 — tracing forcefully disabled"

      env == :test ->
        "config/test.exs — SDK disabled for tests (sdk_disabled: true)"

      exporter() == :otlp ->
        "config/dev.exs — local OTLP → Jaeger (docker compose up -d jaeger otel-collector)"

      env == :dev ->
        "config/config.exs fallback — exporter set to :none by default. Enable in config/dev.exs."

      true ->
        "config/config.exs — exporter set to :none"
    end
  end

  # ── Environment variables ──────────────────────────────────────────

  defp env_vars do
    %{
      "EX_GOCD_NO_OTEL" => System.get_env("EX_GOCD_NO_OTEL", "not set"),
      "OTEL_TRACES_EXPORTER" => System.get_env("OTEL_TRACES_EXPORTER", "not set"),
      "OTEL_EXPORTER_OTLP_ENDPOINT" => System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "not set"),
      "OTEL_SERVICE_NAME" => System.get_env("OTEL_SERVICE_NAME", "not set")
    }
  end

  # ── Instrumentation handlers ───────────────────────────────────────

  # Status of each instrumentation handler:
  #   :phoenix — auto-instrumentation for HTTP requests (Cowboy only, not Bandit)
  #   :ecto — auto-instrumentation for DB queries
  #   :process_propagator — cross-process trace context propagation
  defp instrumentation do
    %{
      phoenix: phoenix_instrumentation_active?(),
      ecto: ecto_instrumentation_active?(),
      process_propagator: process_propagator_loaded?()
    }
  end

  defp phoenix_instrumentation_active? do
    # OpentelemetryPhoenix.setup() attaches telemetry handlers for Phoenix
    # endpoint/route events. However, it only supports Cowboy adapter —
    # Bandit.PhoenixAdapter is explicitly documented as not supported.
    adapter = Application.get_env(:ex_gocd, ExGoCDWeb.Endpoint)[:adapter]

    Code.ensure_loaded?(OpentelemetryPhoenix) and adapter != Bandit.PhoenixAdapter
  end

  defp ecto_instrumentation_active? do
    # OpentelemetryEcto.setup([:ex_gocd, :repo]) attaches handlers for
    # Ecto query events. Check that the module is loaded and the
    # application is configured.
    Code.ensure_loaded?(OpentelemetryEcto) and
      Application.spec(:opentelemetry_ecto) != nil
  end

  defp process_propagator_loaded? do
    Code.ensure_loaded?(OpentelemetryProcessPropagator)
  end

  # ── Collector reachability ─────────────────────────────────────────

  @doc """
  Checks if the configured OTLP collector is reachable.

  Sends a HEAD request to the OTLP endpoint's base URL (e.g. http://localhost:4318).
  Returns `:reachable`, `:unreachable`, or `:not_configured`.
  """
  def collector_reachable? do
    endpoint = otlp_endpoint()

    cond do
      exporter() == :none ->
        :disabled

      endpoint == "not configured" ->
        :not_configured

      true ->
        # Extract base URL from OTLP endpoint (strip /v1/traces suffix if present)
        base =
          endpoint
          |> String.replace(~r{/v1/traces/?$}, "")

        case Req.head(base, retry: false, receive_timeout: 2_000) do
          {:ok, %{status: status}} when status in 200..499 -> :reachable
          {:ok, _} -> :reachable
          {:error, _} -> :unreachable
        end
    end
  end
end
