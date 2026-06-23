defmodule ExGoCD.ConfigRepos.GitHubActionsTranslator do
  @moduledoc """
  Translates a GitHub Actions ExternalPipelineIR into GoCD pipeline attributes.

  ## Mapping rules

  - Workflow `name` → Pipeline `name` (sanitized with prefix)
  - `on.push.branches` → Git material with branch filter
  - `on.schedule` → Pipeline timer (cron)
  - `on.workflow_dispatch` → Manual trigger (no auto material)
  - Jobs → GoCD Stages (one stage per job)
  - Job `runs-on` → Agent resource tags
  - Job `env` → Stage/Job environment_variables
  - Steps (`run:`) → Exec tasks (`type: "exec"`)
  - Steps (`uses:`) → Skipped in translate mode (v1), included as metadata
  - Job `needs` → Stage dependencies (approval + fan-in)
  - `execute_act` mode → single stage with `type: "external"` task
  - `skip` mode → empty stages
  """

  @behaviour ExGoCD.ConfigRepos.Translator

  alias ExGoCD.ConfigRepos.ExternalPipelineIR
  alias ExGoCD.ConfigRepos.TranslatorHelpers

  @impl true
  def translate(%ExternalPipelineIR{source_type: "github_actions"} = ir, selections) do
    mode = Map.get(selections, :mode, "translate")

    case mode do
      "skip" -> {:ok, skip_attrs(ir, selections)}
      "execute_act" -> {:ok, execute_act_attrs(ir, selections)}
      _ -> {:ok, translate_attrs(ir, selections)}
    end
  end

  # --- Skip mode ---

  defp skip_attrs(ir, selections), do: TranslatorHelpers.skip_attrs(ir, selections)

  # --- Translate mode ---

  defp translate_attrs(ir, selections) do
    prefix = Map.get(selections, :pipeline_name_prefix, "")
    selected_jobs = get_in(selections, [:selected_jobs, "included"])
    selected_triggers = get_in(selections, [:selected_triggers, "included"])

    stages = build_translate_stages(ir, selected_jobs)
    materials = build_materials(ir, selected_triggers)
    timer = build_timer(ir)

    attrs = %{
      name: TranslatorHelpers.pipeline_name(ir, prefix),
      group: prefix,
      label_template: "${COUNT}",
      stages: stages,
      materials: materials
    }

    if timer, do: Map.put(attrs, :timer, timer), else: attrs
  end

  defp build_translate_stages(ir, selected_jobs) do
    ir.jobs
    |> TranslatorHelpers.filter_jobs(selected_jobs)
    |> Enum.map(fn {job_name, job_data} ->
      # Filter out action steps in translate mode
      run_steps = Enum.filter(job_data.steps, &(&1.type == "run"))

      tasks =
        Enum.map(run_steps, fn step ->
          %{
            type: "exec",
            command: step.command,
            arguments: [],
            run_if: "passed"
          }
        end)

      %{
        name: job_name,
        approval_type: "success",
        fetch_materials: true,
        clean_working_directory: false,
        jobs: [
          %{
            name: job_name,
            resources: [job_data.runs_on],
            tasks: tasks,
            environment_variables: job_data.env
          }
        ]
      }
    end)
  end

  defp build_materials(ir, selected_triggers) do
    # Check if push trigger should be included
    triggers = ir.triggers

    triggers =
      if selected_triggers do
        Enum.filter(triggers, &(&1.type in selected_triggers))
      else
        triggers
      end

    push_triggers = Enum.filter(triggers, &(&1.type == "push"))

    if push_triggers != [] do
      branches = push_triggers |> Enum.flat_map(&(Map.get(&1, :branches) || [])) |> Enum.uniq()

      [
        %{
          type: "git",
          url: "",
          branch: if(branches == [], do: "main", else: hd(branches)),
          auto_update: true
        }
      ]
    else
      # workflow_dispatch or schedule: no SCM material
      []
    end
  end

  defp build_timer(ir) do
    schedules = Enum.filter(ir.triggers, &(&1.type == "schedule"))

    if schedules != [] do
      hd(schedules).cron
    end
  end

  # --- Execute act mode ---

  defp execute_act_attrs(ir, selections) do
    prefix = Map.get(selections, :pipeline_name_prefix, "")
    selected_jobs = get_in(selections, [:selected_jobs, "included"])

    stages =
      ir.jobs
      |> TranslatorHelpers.filter_jobs(selected_jobs)
      |> Enum.map(fn {job_name, job_data} ->
        event = extract_event_type(ir)

        %{
          name: job_name,
          approval_type: "success",
          fetch_materials: true,
          clean_working_directory: false,
          jobs: [
            %{
              name: job_name,
              resources: [job_data.runs_on],
              tasks: [
                %{
                  type: "external",
                  command: "act",
                  arguments: [],
                  run_if: "passed",
                  external_config: %{
                    executor: "act",
                    workflow_file: ir.source_file,
                    job_name: job_name,
                    event: event
                  }
                }
              ]
            }
          ]
        }
      end)

    %{
      name: TranslatorHelpers.pipeline_name(ir, prefix),
      group: prefix,
      stages: stages,
      materials: build_materials(ir, nil)
    }
  end

  # --- Helpers ---

  defp extract_event_type(ir) do
    case ir.triggers do
      [%{type: type} | _] -> type
      _ -> "push"
    end
  end
end
