defmodule ExGoCD.VsmTracer do
  @moduledoc """
  Value Stream Map tracing helpers. Creates OpenTelemetry spans for the
  pipeline lifecycle: trigger → enqueue → assign → execute → complete.

  Span naming: `resource.action` (e.g. `pipeline.trigger`, `job.assign`).
  All pipeline spans carry `pipeline.name`, `pipeline.counter`;
  stage spans carry `stage.name`, `stage.counter`;
  job spans carry `job.name`, `job.instance_id`;
  agent spans carry `agent.uuid`, `agent.hostname`.

  Attribute convention: OpenTelemetry `dot.case` throughout.

  Uses `OpenTelemetry.Tracer.with_span/3` — spans auto-end when the block
  completes.  When called outside an HTTP request context (e.g. GenServer),
  spans become root spans; when called inside a Phoenix request, they nest
  under the HTTP span.

  ## Cross-process context propagation

  `current_ctx/0` captures the OTEL context of the calling process.
  Pass it to a GenServer as `:parent_ctx`, then call `attach_ctx/1`
  in the GenServer's handler before creating spans.  This links
  scheduler/agent spans under the HTTP trigger span in Jaeger.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @typedoc "Common span attributes shared across all VSM spans"
  @type vsm_attrs :: %{
    optional(:pipeline_name) => String.t(),
    optional(:pipeline_counter) => integer(),
    optional(:stage_name) => String.t(),
    optional(:stage_counter) => integer(),
    optional(:job_name) => String.t(),
    optional(:build_id) => String.t(),
    optional(:agent_uuid) => String.t(),
    optional(:result) => String.t()
  }

  @typedoc "Span attribute keys (as passed to Jaeger/OTLP)"
  @type attr_key :: String.t()

  # ── public helpers ────────────────────────────────────────────────────

  @doc """
  Captures the current OpenTelemetry context (span + baggage).
  Returns `nil` if the SDK is disabled or no span is active.
  Pass this to GenServers as `:parent_ctx` for cross-process linking.
  """
  @spec current_ctx() :: :otel_ctx.t() | nil
  def current_ctx do
    ctx = :otel_ctx.get_current()
    # Return nil if no spans are active (empty context)
    if :otel_tracer.current_span_ctx(ctx) == :undefined, do: nil, else: ctx
  end

  @doc """
  Attaches a previously captured OTEL context to the current process.
  Call this at the start of a GenServer handler before creating spans.
  No-op if ctx is nil.
  """
  @spec attach_ctx(:otel_ctx.t() | nil) :: :ok
  def attach_ctx(nil), do: :ok
  def attach_ctx(ctx) do
    :otel_ctx.attach(ctx)
    :ok
  end

  @doc """
  Wraps `fun` in a span named `span_name` with `attrs` set as span attributes.
  Returns the result of `fun`.
  """
  @spec trace(String.t(), vsm_attrs(), (-> result)) :: result when result: term()
  def trace(span_name, attrs \\ %{}, fun) when is_function(fun, 0) do
    start_opts = %{attributes: attrs}

    Tracer.with_span(span_name, start_opts) do
      fun.()
    end
  end

  @doc """
  Sets an attribute on the currently active span.  Safe no-op if no
  span is active (e.g. SDK disabled).
  """
  @spec set_attr(atom(), term()) :: boolean()
  def set_attr(key, value) do
    Tracer.set_attribute(key, value)
  end

  @doc """
  Sets the status of the currently active span. Status should be
  `:ok` or `{:error, description}`. Safe no-op if no span is active.
  """
  @spec set_status(:ok | {:error, String.t()}) :: boolean()
  def set_status(status) do
    Tracer.set_status(status)
  end

  @doc """
  Injects the current W3C trace context (`traceparent`, `tracestate`) into
  `map` in-place.  Returns the mutated map.  Safe no-op if no span is active
  or the SDK is disabled.

  Use this when sending work to agents — the agent can extract the headers
  and create child spans under the server's trace.
  """
  @spec inject_context(map()) :: map()
  def inject_context(map) when is_map(map) do
    ctx = :otel_ctx.get_current()
    case :otel_tracer.current_span_ctx(ctx) do
      :undefined ->
        map
      {:span_ctx, _version, _trace_id, _span_id, _parent_id, _flags, _tracestate,
       _is_recording, false = _is_valid, _timestamp, _instrumentation_scope} ->
        # span is invalid (e.g. SDK disabled with noop tracer)
        map
      {:span_ctx, _version, <<0::128>>, _span_id, _parent_id, _flags, _tracestate,
       _is_recording, _is_valid, _timestamp, _instrumentation_scope} ->
        # all-zero trace ID (noop tracer) — skip
        map
      _span_ctx ->
        headers = :otel_propagator_text_map.inject(%{})
        Map.merge(map, headers)
    end
  end
end
