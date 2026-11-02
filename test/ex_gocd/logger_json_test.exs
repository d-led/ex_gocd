defmodule ExGoCD.LoggerJSONTest do
  @moduledoc """
  The JSON backend writes the lines Fluent Bit forwards to Loki. They are worth
  reading beside the traces, which needs the identifiers of the span the line was
  written inside.
  """
  use ExUnit.Case, async: true

  alias ExGoCD.LoggerJSON

  # The identifiers a caller would arrive with, as a traceparent header spells
  # them.
  @traceparent "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
  @trace_id "0af7651916cd43dd8448eb211c80319c"
  @span_id "b7ad6b7169203331"

  setup do
    path = Path.join(System.tmp_dir!(), "ex_gocd_json_#{System.unique_integer([:positive])}.log")
    on_exit(fn -> File.rm(path) end)
    {:ok, state} = LoggerJSON.init({LoggerJSON, [path: path]})

    %{path: path, state: state}
  end

  test "a line written inside a span carries its trace and span identifiers", %{
    path: path,
    state: state
  } do
    in_span(fn -> LoggerJSON.handle_event(info_event("job assigned"), state) end)

    entry = last_entry(path)

    assert entry["trace_id"] == @trace_id
    assert entry["span_id"] == @span_id
  end

  test "a line written outside a span carries neither", %{path: path, state: state} do
    LoggerJSON.handle_event(info_event("started"), state)

    entry = last_entry(path)

    refute Map.has_key?(entry, "trace_id")
    refute Map.has_key?(entry, "span_id")
  end

  test "the line still says what was logged and where", %{path: path, state: state} do
    LoggerJSON.handle_event(info_event("job assigned"), state)

    entry = last_entry(path)

    assert entry["level"] == "info"
    assert entry["message"] == "job assigned"
    assert entry["timestamp"] =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/
  end

  defp in_span(fun) do
    token =
      :otel_propagator_text_map.extract(:otel_propagator_trace_context, [
        {"traceparent", @traceparent}
      ])

    try do
      fun.()
    after
      :otel_ctx.detach(token)
    end
  end

  defp info_event(message) do
    {:info, self(), {Logger, message, {{2026, 11, 2}, {12, 34, 56, 789_012}}, [module: nil]}}
  end

  defp last_entry(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> List.last()
    |> Jason.decode!()
  end
end
