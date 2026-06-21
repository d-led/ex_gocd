defmodule ExGoCD.ConfigRepos.GitLabCITranslator do
  @moduledoc """
  Translates a GitLab CI ExternalPipelineIR into GoCD pipeline attributes.

  ## Mapping rules

  - GitLab `stages:` → GoCD stages (ordered)
  - Jobs assigned to stages via `stage:` field
  - `needs:` → Stage dependencies (approval + fan-in)
  - `rules:` → Material branch filters / conditional triggers
  - `variables:` → Pipeline/Stage environment_variables
  - `before_script:/script:/after_script:` → Exec tasks
  - `artifacts:` → GoCD artifact configs
  - `tags:` → Agent resource tags
  - `when: manual` → GoCD `approval_type: "manual"`
  - `image:/services:` → warn/skip in v1
  """

  @behaviour ExGoCD.ConfigRepos.Translator

  alias ExGoCD.ConfigRepos.ExternalPipelineIR
  alias ExGoCD.ConfigRepos.TranslatorHelpers

  @impl true
  def translate(%ExternalPipelineIR{source_type: "gitlab_ci"} = ir, selections) do
    mode = Map.get(selections, :mode, "translate")

    case mode do
      "skip" -> {:ok, skip_attrs(ir, selections)}
      _ -> {:ok, translate_attrs(ir, selections)}
    end
  end

  # --- Skip mode ---

  defp skip_attrs(ir, selections) do
    prefix = Map.get(selections, :pipeline_name_prefix, "")
    %{
      name: TranslatorHelpers.pipeline_name(ir, prefix),
      group: prefix,
      stages: [],
      materials: []
    }
  end

  # --- Translate mode ---

  defp translate_attrs(ir, selections) do
    prefix = Map.get(selections, :pipeline_name_prefix, "")
    selected_jobs = get_in(selections, [:selected_jobs, "included"])

    stages = build_stages(ir, selected_jobs)

    attrs = %{
      name: TranslatorHelpers.pipeline_name(ir, prefix),
      group: prefix,
      label_template: "${COUNT}",
      environment_variables: ir.env_vars,
      stages: stages,
      materials: build_materials(ir)
    }

    attrs
  end

  defp build_stages(ir, selected_jobs) do
    # Group jobs by stage, respecting GitLab's stage ordering
    job_list =
      ir.jobs
      |> TranslatorHelpers.filter_jobs(selected_jobs)
      |> Enum.map(fn {job_name, job_data} -> {job_name, job_data} end)
      |> Enum.sort_by(fn {_, job_data} ->
        idx = Enum.find_index(ir.stages, &(&1 == job_data.stage))
        idx || 999
      end)

    # Group by stage name
    job_list
    |> Enum.group_by(fn {_, job_data} -> job_data.stage end, fn {job_name, job_data} -> {job_name, job_data} end)
    |> Enum.map(fn {stage_name, jobs} ->
      %{
        name: stage_name,
        approval_type: stage_approval_type(jobs),
        fetch_materials: true,
        clean_working_directory: false,
        jobs: Enum.map(jobs, fn {job_name, job_data} ->
          %{
            name: job_name,
            resources: job_data.tags || [],
            tasks: build_tasks(job_data.steps),
            environment_variables: job_data[:env] || %{}
          }
        end)
      }
    end)
  end

  defp stage_approval_type(jobs) do
    # If any job in this stage has when: manual, make it a manual approval stage
    if Enum.any?(jobs, fn {_, job_data} -> job_data[:when] == "manual" end) do
      "manual"
    else
      "success"
    end
  end

  defp build_tasks(steps) when is_list(steps) do
    Enum.map(steps, fn step ->
      %{
        type: "exec",
        command: step.command,
        arguments: [],
        run_if: "passed"
      }
    end)
  end
  defp build_tasks(_), do: []

  defp build_materials(_ir) do
    # GitLab CI triggers via rules, not top-level on: — v1: no SCM material
    # Later: parse rules:if to extract branch filters
    []
  end

  # --- Helpers ---
end
