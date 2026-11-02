defmodule ExGoCD.VsmTracerTest do
  @moduledoc """
  Work handed to an agent carries the trace it belongs to, so the agent's own
  spans hang under the pipeline that asked for them.
  """
  use ExUnit.Case, async: true

  alias ExGoCD.VsmTracer

  # The identifiers a caller would arrive with, as a traceparent header spells
  # them.
  @traceparent "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

  describe "inject_context/1" do
    test "names the span it is called inside" do
      in_span(fn ->
        assert VsmTracer.inject_context(%{}) == %{"traceparent" => @traceparent}
      end)
    end

    test "keeps what the caller put in the map" do
      in_span(fn ->
        assert VsmTracer.inject_context(%{"cookie" => "abc"})["cookie"] == "abc"
      end)
    end

    test "leaves the map alone when there is no span" do
      assert VsmTracer.inject_context(%{"cookie" => "abc"}) == %{"cookie" => "abc"}
    end
  end

  describe "set_status/1" do
    test "is a no-op outside a span, so a caller need not ask" do
      refute VsmTracer.set_status(:ok)
      refute VsmTracer.set_status({:error, "cookie mismatch"})
    end
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
end
