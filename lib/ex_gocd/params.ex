# Copyright 2026 ex_gocd
# Parameter interpolation engine.
# Supports #{param_name} syntax in pipeline labels, task commands,
# arguments, and environment variable values.
#
# Parameters come from:
#   1. Pipeline-level parameters (pipeline.parameters map)
#   2. Trigger-time overrides (options passed to trigger_pipeline)

defmodule ExGoCD.Params do
  @moduledoc """
  Interpolates `\#{param_name}` placeholders in strings and maps.

  ## Examples

      iex> ExGoCD.Params.interpolate("hello \#{name}", %{"name" => "world"})
      "hello world"

      iex> ExGoCD.Params.interpolate(42, %{})
      42

      iex> ExGoCD.Params.interpolate(["echo", "\#{msg}"], %{"msg" => "hi"})
      ["echo", "hi"]

      iex> ExGoCD.Params.interpolate(%{"key" => "\#{val}"}, %{"val" => "replaced"})
      %{"key" => "replaced"}
  """

  @param_pattern ~r/\#\{([a-zA-Z_][a-zA-Z0-9_]*)\}/

  @doc """
  Recursively interpolates all `\#{param}` placeholders in value using the given params map.
  Handles strings, lists, and maps. Passes through other types unchanged.
  """
  @spec interpolate(any(), map()) :: any()
  def interpolate(value, params) when is_binary(value) do
    Regex.replace(@param_pattern, value, fn match, name ->
      case Map.get(params, name) do
        nil -> match
        replacement -> to_string(replacement)
      end
    end)
  end

  def interpolate(values, params) when is_list(values) do
    Enum.map(values, &interpolate(&1, params))
  end

  def interpolate(value, params) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, interpolate(v, params)} end)
  end

  def interpolate(value, _params), do: value

  @doc """
  Merges pipeline-level parameters with trigger-time option overrides.
  Options override pipeline defaults.
  """
  @spec merge_params(map() | nil, map()) :: map()
  def merge_params(pipeline_params, options) do
    pipeline_map = pipeline_params || %{}
    overrides = Map.get(options, :parameters) || Map.get(options, "parameters") || %{}

    # Stringify all keys for consistent lookup
    base = map_stringify_keys(pipeline_map)
    override = map_stringify_keys(overrides)
    Map.merge(base, override)
  end

  defp map_stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end
end
