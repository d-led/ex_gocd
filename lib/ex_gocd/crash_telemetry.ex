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
    ctx = :otel_ctx.get_current()
    details = crash_details(metadata)
    conn = metadata[:conn]

    # Audited whether or not a trace is recording: a crash is not a debugging aid.
    ExGoCD.AuditLog.Events.server_crash(source_of(conn), details)
    record_span_event(ctx, details)
  end

  defp crash_details(metadata) do
    conn = metadata[:conn]

    %{
      "exception.kind" => inspect(metadata[:kind]),
      "exception.message" => exception_message(metadata[:reason]),
      "stacktrace" => formatted_stacktrace(metadata[:stacktrace]),
      "http.method" => request_field(conn, :method),
      "http.url" => request_field(conn, :request_path)
    }
  end

  defp formatted_stacktrace(nil), do: nil
  defp formatted_stacktrace(stacktrace), do: Exception.format_stacktrace(stacktrace)

  defp request_field(nil, _field), do: nil
  defp request_field(conn, field), do: Map.get(conn, field)

  defp source_of(nil), do: "background"
  defp source_of(conn), do: "#{conn.method} #{conn.request_path}"

  # Only record a span event if there is an active recording span to put it on.
  defp record_span_event(ctx, details) do
    case :otel_tracer.current_span_ctx(ctx) do
      {:span_ctx, _version, _trace_id, _span_id, _parent_id, _flags, _tracestate, true, true,
       _timestamp, _instrumentation_scope} ->
        :otel_span.add_event(:otel_tracer.current_span_ctx(ctx), "exception", details)

      _ ->
        :ok
    end
  end

  defp exception_message(%{message: msg}) when is_binary(msg), do: msg
  defp exception_message(error), do: inspect(error)
end
