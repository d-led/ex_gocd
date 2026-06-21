defmodule ExGoCD.Otel do
  @moduledoc """
  Optional OpenTelemetry setup for ex_gocd CI server.

  Set EX_GOCD_NO_OTEL=1 to disable. OTel pushes spans to the collector
  (localhost:4318) which forwards to Jaeger. Fails gracefully if collector
  is unavailable — the app works fine without it.
  """

  @doc "Initialize OTel SDK. Called at app start. Non-blocking on failure."
  def setup do
    config = Application.get_env(:ex_gocd, :otel, [])
    exporter = Keyword.get(config, :exporter, :otlp)
    endpoint = Keyword.get(config, :otlp_endpoint, "http://localhost:4318")

    case Application.ensure_all_started(:opentelemetry) do
      {:ok, _} -> :ok
      {:error, _} ->
        IO.puts("[OTel] opentelemetry app failed to start — traces disabled")
        :ok
    end

    try do
      :opentelemetry.set_default_tracer({:otel_tracer_default, %{}})

      processors =
        if exporter == :otlp do
          [{:otel_batch_processor,
            %{exporter: {:opentelemetry_exporter,
              %{protocol: :http_protobuf, endpoints: [endpoint], compression: :gzip}}}}]
        else
          []
        end

      apply(:opentelemetry, :set_processor_pipeline, [processors])
      IO.puts("[OTel] Tracing enabled → #{endpoint}")
    rescue
      e -> IO.puts("[OTel] Setup failed: #{Exception.message(e)} — traces disabled")
    end

    :ok
  end

  # Pipeline VSM tracing helpers (called from pipelines context)
  def vsm_tracer, do: :ex_gocd_vsm_tracer
end
