defmodule ExGoCDWeb.ControllerHelpers do
  @moduledoc """
  Shared helpers for API controllers.

  Extracted from duplicated `defp` functions across multiple controllers
  (template_controller, pipeline_config_controller, user_controller,
  job_controller, stage_controller).
  """

  @doc """
  Formats Ecto changeset errors into a human-readable map.
  """
  def format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc """
  Formats a DateTime/NaiveDateTime to ISO 8601 string. Returns nil for nil.
  """
  def format_ts(nil), do: nil
  def format_ts(dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")

  @doc """
  Parses an integer from a binary string, defaulting to 0 on parse errors or nil.
  """
  def parse_offset(nil), do: 0

  def parse_offset(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end
end
