defmodule ExGoCD.ConfigRepos.GitHubActionsParser do
  @moduledoc """
  Parses GitHub Actions workflow YAML files into ExternalPipelineIR.

  Uses the published JSON Schema (github-workflow.json) as reference for field names and types.
  Schema source: https://json.schemastore.org/github-workflow.json

  ## v1 Scope
  - Parses: name, on (push, schedule, workflow_dispatch), jobs.<id> (runs-on, needs, steps, env)
  - Steps: run: → exec step, uses: → action reference (warned but not executed)
  - Matrix: recorded as metadata, not expanded
  - Excluded: pull_request, workflow_call, services, container, permissions, concurrency
  """

  alias ExGoCD.ConfigRepos.{ExternalPipelineIR, ParserHelpers}

  @doc """
  Parses a GitHub Actions workflow YAML string into an ExternalPipelineIR.

  Returns `{:ok, ir}` or `{:error, reason}`.

  ## Examples

      iex> yaml = "name: CI\\\\non: push\\\\njobs:\\\\n  build:\\\\n    runs-on: ubuntu-latest\\\\n    steps:\\\\n      - run: echo hi"
      iex> {:ok, ir} = GitHubActionsParser.parse_workflow(yaml, ".github/workflows/ci.yml")
      iex> ir.name
      "CI"
  """
  @spec parse_workflow(String.t(), String.t()) :: {:ok, ExternalPipelineIR.t()} | {:error, String.t()}
  def parse_workflow(yaml_string, source_file) when is_binary(yaml_string) and is_binary(source_file) do
    with {:ok, parsed} <- ParserHelpers.parse_yaml(yaml_string),
         :ok <- ParserHelpers.ensure_map(parsed, "workflow YAML") do
      name = Map.get(parsed, "name", stem_from(source_file))
      triggers = extract_triggers(parsed["on"])
      env_vars = extract_env_vars(parsed["env"])
      jobs_map = extract_jobs(parsed["jobs"] || %{})

      stages = jobs_map |> Map.values() |> Enum.map(& &1.stage) |> Enum.uniq()

      ir = ExternalPipelineIR.new(
        source_type: "github_actions",
        source_file: source_file,
        name: name,
        triggers: triggers,
        env_vars: env_vars,
        stages: stages,
        jobs: jobs_map
      )

      {:ok, ir}
    end
  end

  # --- YAML parsing ---

  defp stem_from(file_path), do: ParserHelpers.stem_from(file_path)

  # --- Triggers ---

  defp extract_triggers(nil), do: []

  defp extract_triggers(on_section) when is_binary(on_section) do
    # bare "on: push"
    [%{type: on_section}]
  end

  defp extract_triggers(on_section) when is_list(on_section) do
    # "on: [push, pull_request]"
    Enum.map(on_section, fn event -> %{type: event} end)
  end

  defp extract_triggers(on_section) when is_map(on_section) do
    Enum.flat_map(on_section, fn {event, config} ->
      case event do
        "push" -> [build_push_trigger(config)]
        "schedule" -> build_schedule_triggers(config)
        "workflow_dispatch" -> [build_dispatch_trigger(config)]
        _ -> [] # pull_request, workflow_call, etc. excluded in v1
      end
    end)
  end

  defp build_push_trigger(nil), do: %{type: "push"}
  defp build_push_trigger(config) when is_map(config) do
    %{type: "push", branches: config["branches"] || [], tags: config["tags"] || []}
  end
  defp build_push_trigger(_), do: %{type: "push"}

  defp build_schedule_triggers(schedules) when is_list(schedules) do
    Enum.map(schedules, fn s ->
      %{type: "schedule", cron: s["cron"]}
    end)
  end
  defp build_schedule_triggers(_), do: []

  defp build_dispatch_trigger(config) when is_map(config) do
    base = %{type: "workflow_dispatch"}
    if Map.has_key?(config, "inputs") do
      Map.put(base, :inputs, config["inputs"])
    else
      base
    end
  end
  defp build_dispatch_trigger(_), do: %{type: "workflow_dispatch"}

  # --- Environment variables ---

  defp extract_env_vars(nil), do: %{}
  defp extract_env_vars(env) when is_map(env), do: env
  defp extract_env_vars(_), do: %{}

  # --- Jobs ---

  defp extract_jobs(jobs) when is_map(jobs) do
    job_order = Map.keys(jobs)

    # First pass: collect raw job data
    raw = for {job_id, job_data} <- jobs, into: %{} do
      {job_id, extract_single_job(job_id, job_data, job_order)}
    end

    # Second pass: add needs-based ordering (jobs without needs come first in stage order)
    # For now, use job_order as-is from YAML
    raw
  end

  defp extract_jobs(_), do: %{}

  defp extract_single_job(job_id, job_data, _job_order) when is_map(job_data) do
    needs = case job_data["needs"] do
      n when is_list(n) -> n
      n when is_binary(n) -> [n]
      _ -> []
    end

    steps = extract_steps(job_data["steps"] || [])
    runs_on = job_data["runs-on"] || "ubuntu-latest"
    env = job_data["env"] || %{}
    if_statement = job_data["if"]

    %{
      stage: job_id,
      needs: needs,
      runs_on: runs_on,
      steps: steps,
      env: Map.merge(%{}, env),
      if: if_statement
    }
  end
  defp extract_single_job(job_id, runs_on, _) when is_binary(runs_on) do
    %{stage: job_id, needs: [], runs_on: runs_on, steps: [], env: %{}}
  end

  # --- Steps ---

  defp extract_steps(steps) when is_list(steps) do
    Enum.map(steps, fn step ->
      cond do
        Map.has_key?(step, "run") ->
          %{type: "run", command: step["run"], name: step["name"], shell: step["shell"]}
        Map.has_key?(step, "uses") ->
          %{type: "action", uses: step["uses"], name: step["name"], with: step["with"] || %{}}
        true ->
          %{type: "unknown", name: step["name"]}
      end
    end)
  end

  defp extract_steps(_), do: []
end
