defmodule ExGoCD.CrashTelemetry do
  @moduledoc """
  Attaches telemetry handlers that emit OTel span events for crashes.

  Covers:
  - Phoenix endpoint errors (unhandled exceptions in controllers/LiveViews)
  - Phoenix router dispatch exceptions

  Each crash creates a span event with error details so they're visible in Jaeger.
  """

  @doc """
  Attaches all crash telemetry handlers. Safe to call when OTel is disabled
  (the handler does nothing if no active span).
  """
  def attach do
    :telemetry.attach(
      "ex_gocd-crash-endpoint",
      [:phoenix, :endpoint, :exception],
      &handle_exception/4,
      nil
    )

    :telemetry.attach(
      "ex_gocd-crash-router",
      [:phoenix, :router_dispatch, :exception],
      &handle_exception/4,
      nil
    )

    :ok
  end

  defp handle_exception(_event, _measurements, metadata, _config) do
    kind = metadata[:kind]
    reason = metadata[:reason]
    stacktrace = metadata[:stacktrace]
    conn = metadata[:conn]

    ctx = :otel_ctx.get_current()
    span_ctx = :otel_tracer.current_span_ctx(ctx)

    # Audit the crash
    crash_details = %{
      "exception.kind" => inspect(kind),
      "exception.message" => exception_message(reason),
      "stacktrace" => stacktrace && Exception.format_stacktrace(stacktrace),
      "http.method" => conn && conn.method,
      "http.url" => conn && conn.request_path
    }

    source = if conn, do: "#{conn.method} #{conn.request_path}", else: "background"
    ExGoCD.AuditLog.Events.server_crash(source, crash_details)

    # Only record OTel span event if there's an active recording span
    case span_ctx do
      {:span_ctx, _version, _trace_id, _span_id, _parent_id, _flags, _tracestate,
       true = _is_recording, true = _is_valid, _timestamp, _instrumentation_scope} ->
        details = %{
          "exception.kind" => inspect(kind),
          "exception.message" => exception_message(reason),
          "http.method" => conn && conn.method,
          "http.url" => conn && conn.request_path
        }

        :otel_span.add_event(:otel_tracer.current_span_ctx(ctx), "exception", details)

      _ ->
        :ok
    end
  end

  defp exception_message(%{message: msg}) when is_binary(msg), do: msg
  defp exception_message(error), do: inspect(error)
end
