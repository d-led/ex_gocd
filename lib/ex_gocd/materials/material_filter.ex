defmodule ExGoCD.Materials.MaterialFilter do
  @moduledoc """
  Implements GoCD's material filter logic for selectively triggering pipelines
  based on which files changed.

  Mirrors GoCD's `IgnoredFiles` and `Filter` classes:
  - `filter_ignore` (ignore patterns): comma-separated globs in Material schema
  - `filter_include` (include patterns): if set, ONLY these paths trigger
  - Empty filter = all changes pass through

  ## Pattern syntax (GoCD-compatible)
  - `*.doc` — matches .doc files in root only
  - `**/*.doc` — matches .doc files at any depth
  - `test/**/*` — ignores everything under test/
  - `foo*/**/*.doc` — directory wildcard

  ## Behavior (mirrors GoCD's IgnoredFiles.shouldIgnore + Modifications.shouldBeIgnoredByFilterIn)
  - If ALL modifications are ignored → skip trigger
  - If ANY modification is not ignored → trigger
  - Include filter (inverted): if set, ONLY matching paths trigger
  - Empty filter → all pass
  """

  @doc """
  Returns true if ALL modifications in the list should be ignored based on the material's filter.
  Mirrors GoCD's `Modifications.shouldBeIgnoredByFilterIn()`.
  """
  @spec all_ignored?(Material.t(), [map()]) :: boolean()
  def all_ignored?(nil, _modifications), do: false
  def all_ignored?(%{filter_ignore: [], filter_include: []}, _modifications), do: false

  def all_ignored?(material, modifications) when is_list(modifications) do
    paths = Enum.map(modifications, &extract_path/1)

    cond do
      is_list(material.filter_include) and material.filter_include != [] ->
        not Enum.any?(paths, &matches_any_pattern?(&1, material.filter_include))

      is_list(material.filter_ignore) and material.filter_ignore != [] ->
        Enum.all?(paths, &matches_any_pattern?(&1, material.filter_ignore))

      true ->
        false
    end
  end

  @doc """
  Returns true if the given path matches any of the provided glob patterns.
  Uses GoCD-compatible glob → regex translation.
  """
  @spec matches_any_pattern?(String.t(), [String.t()]) :: boolean()
  def matches_any_pattern?(path, patterns) when is_list(patterns) do
    Enum.any?(patterns, &pattern_matches?(&1, path))
  end

  @doc """
  Tests a single pattern against a path using GoCD-compatible glob rules.
  """
  @spec pattern_matches?(String.t(), String.t()) :: boolean()
  def pattern_matches?(pattern, path) do
    regex = glob_to_regex(pattern)
    String.match?(path, regex)
  end

  # GoCD-compatible glob → regex.
  # Applies glob replacements BEFORE escaping, so ** and * don't get escaped.
  defp glob_to_regex(pattern) do
    result =
      pattern
      |> String.replace("**/", "<<DEEP>>")
      |> String.replace("**", "<<DEEP>>")
      |> String.replace("*", "<<STAR>>")
      |> String.replace("?", "<<QUEST>>")
      |> Regex.escape()
      |> String.replace("<<DEEP>>", "([^/]*/)*")
      |> String.replace("<<STAR>>", "[^/]*")
      |> String.replace("<<QUEST>>", "[^/]")

    ~r/^#{result}$/i
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp extract_path(%{path: path}) when is_binary(path), do: path
  defp extract_path(%{"path" => path}) when is_binary(path), do: path
  defp extract_path(%{file_name: name}) when is_binary(name), do: name
  defp extract_path(%{"file_name" => name}) when is_binary(name), do: name
  defp extract_path(%{comment: comment}), do: extract_first_path_from_text(comment)
  defp extract_path(%{"comment" => comment}), do: extract_first_path_from_text(comment)
  defp extract_path(_), do: ""

  defp extract_first_path_from_text(text) when is_binary(text) do
    # Try to extract a file path from a commit message
    # Common patterns: "Modified foo/bar.txt" or just "foo/bar.txt"
    case Regex.run(~r/(?:Modified\s+)?([\w.\/-]+\.[\w]+)/, text) do
      [_, path] -> path
      nil -> ""
    end
  end
end
