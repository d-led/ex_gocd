defmodule ExGoCD.ConfigRepos.GitLabCIParser do
  @moduledoc """
  Parses GitLab CI YAML files into ExternalPipelineIR.

  Uses the published JSON Schema (gitlab-ci.json) as reference for field names and types.
  Schema source: https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json

  ## v1 Scope
  - Parses: stages, variables, include, jobs with stage/needs/script/before_script/after_script/rules/tags/when
  - Include resolution: local, remote, project, template (paths extracted, full resolution in IncludeResolver)
  - Excluded: extends (template merging), image/services, retry, interruptible, resource_group
  """

  alias ExGoCD.ConfigRepos.{ExternalPipelineIR, ParserHelpers}

  @doc """
  Parses a GitLab CI YAML string into an ExternalPipelineIR.

  Returns `{:ok, ir}` or `{:error, reason}`.
  """
  @spec parse_gitlab_ci(String.t(), String.t()) :: {:ok, ExternalPipelineIR.t()} | {:error, String.t()}
  def parse_gitlab_ci(yaml_string, source_file) when is_binary(yaml_string) and is_binary(source_file) do
    with {:ok, parsed} <- parse_yaml(yaml_string),
         :ok <- ensure_map(parsed) do
      name = pipeline_name(parsed, source_file)
      stages = extract_stages(parsed["stages"])
      env_vars = extract_env_vars(parsed["variables"])
      includes = extract_includes(parsed["include"])
      jobs_map = extract_jobs(parsed, stages)

      ir = ExternalPipelineIR.new(
        source_type: "gitlab_ci",
        source_file: source_file,
        name: name,
        triggers: [], # GitLab CI triggers via rules, not top-level on:
        env_vars: env_vars,
        stages: stages,
        jobs: jobs_map,
        includes: includes
      )

      {:ok, ir}
    end
  end

  # --- YAML parsing ---

  defp parse_yaml(content), do: ParserHelpers.parse_yaml(content)
  defp ensure_map(data), do: ParserHelpers.ensure_map(data, "GitLab CI YAML")

  defp pipeline_name(parsed, source_file) do
    case parsed["workflow"] do
      %{"name" => name} when is_binary(name) -> name
      _ ->
        source_file
        |> Path.basename()
        |> Path.rootname()
        |> String.trim_leading(".")
    end
  end

  # --- Stages ---

  defp extract_stages(nil), do: []
  defp extract_stages(stages) when is_list(stages), do: stages
  defp extract_stages(_), do: []

  # --- Env vars ---

  defp extract_env_vars(nil), do: %{}
  defp extract_env_vars(vars) when is_map(vars) do
    # GitLab variables can be string values or {value:, description:, options:} maps
    Map.new(vars, fn {k, v} ->
      val = if is_map(v), do: Map.get(v, "value", to_string(v)), else: to_string(v)
      {k, val}
    end)
  end
  defp extract_env_vars(_), do: %{}

  # --- Includes ---

  defp extract_includes(nil), do: []
  defp extract_includes(includes) when is_list(includes) do
    Enum.flat_map(includes, &extract_single_include/1)
  end
  defp extract_includes(single) when is_map(single), do: extract_single_include(single)
  defp extract_includes(single) when is_binary(single), do: [single]

  defp extract_single_include(include) when is_binary(include), do: [include]

  defp extract_single_include(include) when is_map(include) do
    cond do
      Map.has_key?(include, "local") -> [include["local"]]
      Map.has_key?(include, "remote") -> [include["remote"]]
      Map.has_key?(include, "project") -> [include["file"]]
      Map.has_key?(include, "template") -> [include["template"]]
      true -> []
    end
  end

  # --- Jobs ---

  # GitLab CI top-level keys can be: stages, variables, include, workflow, default,
  # plus special keys like ".pre", ".post", and hidden keys starting with "."
  # Everything else is a job.
  @reserved_keys ~w(stages variables include workflow default spec before_script after_script image services cache pages)

  defp extract_jobs(parsed, stages) when is_map(parsed) do
    parsed
    |> Enum.reject(fn {key, _} ->
      String.starts_with?(key, ".") or key in @reserved_keys
    end)
    |> Map.new(fn {job_id, job_data} ->
      {job_id, extract_single_job(job_id, job_data, stages)}
    end)
  end

  defp extract_single_job(_job_id, job_data, _stages) when is_map(job_data) do
    stage = job_data["stage"] || "test"
    needs = extract_job_needs(job_data["needs"])
    steps = extract_job_steps(job_data)
    tags = job_data["tags"] || []
    rules = extract_rules(job_data["rules"])
    when_val = job_data["when"]

    %{
      stage: stage,
      needs: needs,
      steps: steps,
      tags: List.wrap(tags),
      rules: rules,
      when: when_val
    }
  end
  defp extract_single_job(job_id, _job_data, _stages) do
    %{stage: job_id, needs: [], steps: [], tags: [], rules: [], when: nil}
  end

  defp extract_job_needs(nil), do: []
  defp extract_job_needs(needs) when is_list(needs) do
    Enum.map(needs, fn
      n when is_binary(n) -> n
      n when is_map(n) -> n["job"] || n["pipeline"]
    end)
  end
  defp extract_job_needs(needs) when is_binary(needs), do: [needs]

  defp extract_job_steps(job_data) when is_map(job_data) do
    before = extract_script_commands(job_data["before_script"], "before_script")
    script = extract_script_commands(job_data["script"], "script")
    after_cmds = extract_script_commands(job_data["after_script"], "after_script")

    before ++ script ++ after_cmds
  end

  defp extract_script_commands(nil, _type), do: []
  defp extract_script_commands(commands, type) when is_binary(commands) do
    [%{type: type, command: commands}]
  end
  defp extract_script_commands(commands, type) when is_list(commands) do
    Enum.map(commands, fn
      cmd when is_binary(cmd) -> %{type: type, command: cmd}
      cmd when is_list(cmd) -> %{type: type, command: Enum.join(cmd, " ")}
      cmd -> %{type: type, command: to_string(cmd)}
    end)
  end

  defp extract_rules(nil), do: []

  defp extract_rules(rules) when is_list(rules) do
    Enum.map(rules, fn
      rule when is_map(rule) ->
        %{}
        |> maybe_put(:if, rule["if"])
        |> maybe_put(:when, rule["when"])
        |> maybe_put(:changes, rule["changes"])
        |> maybe_put(:exists, rule["exists"])
        |> maybe_put(:allow_failure, rule["allow_failure"])
      _ -> %{}
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
