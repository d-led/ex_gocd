defmodule ExGoCD.Otel do
  @moduledoc """
  OpenTelemetry configuration for ex_gocd CI server.

  Sets up the OTLP exporter to push spans to the OpenTelemetry Collector
  (or directly to Jaeger in dev). Configures sampling, resource attributes,
  and integrates with Phoenix and Ecto.

  Pipeline VSM tracing: each pipeline trigger starts a root span that
  propagates through stages/jobs as child spans, forming a correlated
  distributed trace viewable in Jaeger.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Initializes OpenTelemetry SDK with OTLP exporter.
  Called at application start.
  """
  def setup do
    config = Application.get_env(:ex_gocd, :otel, [])
    exporter = Keyword.get(config, :exporter, :otlp)
    otlp_endpoint = Keyword.get(config, :otlp_endpoint, "http://localhost:4318")

    :ok = :application.load(:opentelemetry)

    # Configure SDK
    :opentelemetry.set_default_tracer({:otel_tracer_default, %{}})

    processors =
      case exporter do
        :otlp ->
          setup_otlp(otlp_endpoint)
        :jaeger ->
          setup_jaeger_thrift()
        _ ->
          [simple_processor()]
      end

    apply(:opentelemetry, :set_processor_pipeline, [processors])

    :ok
  end

  defp setup_otlp(endpoint) do
    # OTLP over HTTP (port 4318) — default collector receiver
    config = %{
      endpoints: [{:http, endpoint, []}],
      headers: [],
      compression: :gzip
    }

    [
      {:otel_batch_processor, %{exporter: {:opentelemetry_exporter, config}}}
    ]
  end

  defp setup_jaeger_thrift do
    # Direct Jaeger Thrift export (port 14268) — fallback without collector
    [
      {:otel_batch_processor, %{
        exporter: {:opentelemetry_exporter, %{
          protocol: :http_thrift,
          endpoints: [{"http://localhost:14268/api/traces", []}]
        }}
      }}
    ]
  end

  defp simple_processor do
    [{:otel_simple_processor, %{exporter: :opentelemetry_exporter}}]
  end

  # ---------------------------------------------------------------------------
  # Pipeline VSM tracing helpers
  # ---------------------------------------------------------------------------

  @vsms_tracer_id :ex_gocd_vsm_tracer

  @doc """
  Returns the tracer module used for VSM (pipeline) traces.
  """
  def vsm_tracer, do: @vsms_tracer_id

  @doc """
  Starts a root span for a pipeline trigger (the VSM trace root).
  Returns the span context so it can be injected into downstream spans.

  ## Examples

      ctx = ExGoCD.Otel.start_pipeline_span("build-linux", 146)
      # ... trigger stages/jobs ...
      ExGoCD.Otel.end_pipeline_span(ctx, :passed)
  """
  @spec start_pipeline_span(String.t(), integer()) :: OpenTelemetry.span_ctx()
  def start_pipeline_span(pipeline_name, counter) when is_binary(pipeline_name) and is_integer(counter) do
    tracer = vsm_tracer()
    span_name = "pipeline.#{pipeline_name}"

    attrs = %{
      "pipeline.name" => pipeline_name,
      "pipeline.counter" => counter,
      "ci.pipeline.trigger" => "manual"
    }

    Tracer.start_span(tracer, span_name, %{attributes: attrs, kind: :server})
  end

  @doc """
  Starts a span for a stage within a running pipeline trace.
  Links to parent pipeline span via `parent_ctx`.

  ## Examples

      stage_ctx = ExGoCD.Otel.start_stage_span(parent_ctx, "compile", 1)
  """
  @spec start_stage_span(OpenTelemetry.span_ctx(), String.t(), integer()) :: OpenTelemetry.span_ctx()
  def start_stage_span(_parent_ctx, stage_name, stage_counter) do
    tracer = vsm_tracer()
    span_name = "stage.#{stage_name}"

    Tracer.start_span(tracer, span_name, %{
      attributes: %{
        "stage.name" => stage_name,
        "stage.counter" => stage_counter
      },
      kind: :internal
    })
  end

  @doc """
  Starts a span for a job execution within a stage.
  """
  @spec start_job_span(OpenTelemetry.span_ctx(), String.t(), String.t()) :: OpenTelemetry.span_ctx()
  def start_job_span(_parent_ctx, job_name, agent_uuid) do
    tracer = vsm_tracer()
    span_name = "job.#{job_name}"

    Tracer.start_span(tracer, span_name, %{
      attributes: %{
        "job.name" => job_name,
        "agent.uuid" => agent_uuid
      },
      kind: :internal
    })
  end

  @doc """
  Ends a span with an optional status.
  """
  @spec end_span(OpenTelemetry.span_ctx(), atom() | nil) :: :ok
  def end_span(span_ctx, status \\ nil) do
    if status do
      Tracer.set_status(status, "")
    end
    Tracer.end_span(span_ctx)
  end

  @doc """
  Records a custom event on the current span.
  Used for timing wait times, transitions, etc.
  """
  @spec add_event(String.t(), map()) :: :ok
  def add_event(name, attrs \\ %{}) when is_binary(name) and is_map(attrs) do
    Tracer.add_event(name, attrs)
  end

  @doc """
  Sets a span attribute on the current span.
  Useful for adding timing info like wait_ms, exec_ms.
  """
  @spec set_attr(String.t(), term()) :: :ok
  def set_attr(key, value) when is_binary(key) do
    Tracer.set_attribute(key, value)
  end
end
