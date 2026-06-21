defmodule ExGoCD.VsmTracer do
  @moduledoc """
  Value Stream Map tracing helpers. Creates OpenTelemetry spans for the
  pipeline lifecycle: trigger → schedule → assign → execute → complete.

  All spans carry `pipeline.name`, `pipeline.counter`, `stage.name`,
  `stage.counter`, `job.name`, `build.id` attributes so Jaeger can
  correlate them into a single VSM trace.

  Uses `OpenTelemetry.Tracer.with_span/3` — spans auto-end when the block
  completes.  When called outside an HTTP request context (e.g. GenServer),
  spans become root spans; when called inside a Phoenix request, they nest
  under the HTTP span.
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

  # ── public helpers ────────────────────────────────────────────────────

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
  Creates a span and sets attributes from a keyword list, then runs `fun`.
  Convenience for callers that prefer keyword lists.
  """
  @spec trace_kw(String.t(), keyword(), (-> result)) :: result when result: term()
  def trace_kw(span_name, kw_attrs \\ [], fun) when is_function(fun, 0) do
    trace(span_name, Map.new(kw_attrs), fun)
  end

  @doc """
  Sets an attribute on the currently active span.  Safe no-op if no
  span is active (e.g. SDK disabled).
  """
  @spec set_attr(atom(), term()) :: boolean()
  def set_attr(key, value) do
    Tracer.set_attribute(key, value)
  end
end
