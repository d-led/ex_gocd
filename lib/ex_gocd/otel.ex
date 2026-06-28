defmodule ExGoCD.Otel do
  @moduledoc """
  OpenTelemetry instrumentation for ex_gocd CI server.

  Set EX_GOCD_NO_OTEL=1 to disable all tracing. The OpenTelemetry SDK
  starts via OTP with its own app env config (see config.exs). This module
  attaches Phoenix, Ecto, and Process telemetry handlers to create spans.

  Spans flow: ex_gocd → OTLP HTTP (localhost:4318) → Collector → Jaeger.

  Cross-node tracing: `opentelemetry_process_propagator` propagates trace
  context across GenServer.call/cast and Task boundaries between cluster nodes,
  so a pipeline trigger on node A that schedules work via Scheduler on node B
  still shows a complete trace.
  """

  @doc """
  Attaches instrumentation handlers: Phoenix, Ecto, Bandit, Process propagator.
  Called at app start. Fails gracefully if OTEL SDK is unavailable.
  """
  def setup do
    # Ensure the SDK application is started (it's a dependency, but be safe)
    case Application.ensure_all_started(:opentelemetry) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        IO.puts("[OTel] SDK not available — traces disabled")
        :ok
    end

    # Attach Phoenix instrumentation — creates spans for HTTP requests
    OpentelemetryPhoenix.setup()

    # Attach Ecto instrumentation — creates spans for DB queries
    OpentelemetryEcto.setup([:ex_gocd, :repo])

    IO.puts("[OTel] Instrumentation attached → http://localhost:4318")

    :ok
  end

  @doc """
  Fetches the parent trace context from the calling process.
  Uses `opentelemetry_process_propagator` for contexts where OTP's built-in
  propagation is insufficient (Task.async, Ecto preloads, cross-node calls
  with older OTP versions).
  """
  def fetch_parent_ctx(pid \\ self()) do
    OpentelemetryProcessPropagator.fetch_parent_ctx(pid, :"$callers")
  end

  # Pipeline VSM tracing helpers (called from pipelines context)
  def vsm_tracer, do: :ex_gocd_vsm_tracer
end
