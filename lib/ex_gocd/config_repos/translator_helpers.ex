defmodule ExGoCD.ConfigRepos.TranslatorHelpers do
  @moduledoc """
  Shared helpers used by GitHub Actions and GitLab CI translators.
  """

  @doc """
  Sanitizes and prefixes a pipeline name.
  """
  def pipeline_name(ir, prefix) do
    name = ir.name |> String.replace(~r/[^a-zA-Z0-9_-]/, "-") |> String.trim("-")

    if prefix != "" and prefix != nil do
      "#{prefix}-#{name}"
    else
      name
    end
  end

  @doc """
  Filters jobs by a selected list, or returns all if nil.
  """
  def filter_jobs(jobs, nil), do: jobs

  def filter_jobs(jobs, selected) when is_list(selected) do
    Enum.filter(jobs, fn {name, _} -> name in selected end)
  end

  @doc """
  Reads what a selection chose from one of its lists.

  A selection's lists reach here in two shapes: the list itself, as a
  `ConfigRepoFileSelection` stores it, or a map with an `"included"` key. Either
  way a list that names nothing means nothing was chosen, and a file nobody chose
  anything from is translated whole rather than into nothing.
  """
  def chosen(selections, key) do
    case Map.get(selections, key) do
      nil -> nil
      %{"included" => included} -> named(included)
      list when is_list(list) -> named(list)
    end
  end

  defp named([]), do: nil
  defp named(names), do: names

  @doc """
  Builds a skip-mode attributes map with only the pipeline name and empty stages/materials.
  """
  def skip_attrs(ir, selections) do
    prefix = Map.get(selections, :pipeline_name_prefix, "")

    %{
      name: pipeline_name(ir, prefix),
      group: prefix,
      stages: [],
      materials: []
    }
  end
end
