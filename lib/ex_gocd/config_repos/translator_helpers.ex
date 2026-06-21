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
end
