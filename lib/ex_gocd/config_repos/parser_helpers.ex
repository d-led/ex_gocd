defmodule ExGoCD.ConfigRepos.ParserHelpers do
  @moduledoc """
  Shared YAML parsing helpers used by GitHub Actions and GitLab CI parsers.
  """

  @doc """
  Parses a YAML string into Elixir terms.
  """
  def parse_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, "YAML parse error: #{inspect(reason)}"}
    end
  end

  @doc """
  Validates that parsed data is a map (not a list or scalar).
  Accepts a label for the error message.
  """
  def ensure_map(data, label \\ "YAML")
  def ensure_map(data, _label) when is_map(data), do: :ok

  def ensure_map(_data, label),
    do: {:error, "#{label} must parse to a mapping, not a list or scalar"}

  @doc """
  Extracts the stem (filename without extension) from a file path.
  """
  def stem_from(file_path) do
    file_path |> Path.basename() |> Path.rootname()
  end
end
