# Copyright 2026 ex_gocd
# Parses GoCD-style pipeline-as-code definitions from YAML/JSON files.

defmodule ExGoCD.ConfigRepos.Parser do
  @moduledoc """
  Parses pipeline configuration definitions from config repo files.

  Supported format (YAML):

      pipelines:
        - name: my-pipeline
          group: default
          label_template: "${COUNT}"
          lock_behavior: none
          parameters:
            DEPLOY_ENV: staging
          materials:
            - type: git
              url: https://github.com/example/repo.git
              branch: main
          stages:
            - name: build
              approval_type: success
              jobs:
                - name: compile
                  resources: []
                  tasks:
                    - type: exec
                      command: make
                      arguments: ["build"]
                - name: test
                  resources: []
                  tasks:
                    - type: exec
                      command: make
                      arguments: ["test"]
  """

  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  @doc """
  Parses a YAML or JSON string and upserts pipelines into the database.

  Supports multi-document YAML (docs separated by `\\n---\\n`), JSON, and the
  GoCD-native YAML format where pipelines are named map entries rather than list items.

  Returns {:ok, count} with number of pipelines upserted, or {:error, reason}.
  """
  @spec parse_and_upsert(String.t()) :: {:ok, integer()} | {:error, String.t()}
  def parse_and_upsert(content) when is_binary(content) do
    # Split on YAML document separator (used by poller when concatenating files)
    docs = split_documents(content)

    results =
      Enum.reduce_while(docs, {:ok, 0}, fn doc, {:ok, acc} ->
        trimmed = String.trim(doc)

        if trimmed == "" do
          {:cont, {:ok, acc}}
        else
          case parse_and_upsert_single(trimmed) do
            {:ok, count} -> {:cont, {:ok, acc + count}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end
      end)

    case results do
      {:ok, 0} -> {:error, "no pipelines found in config file"}
      other -> other
    end
  end

  defp parse_and_upsert_single(content) do
    with {:ok, parsed} <- parse_content(content),
         {:ok, pipelines} <- extract_pipelines(parsed),
         {:ok, count} <- upsert_pipelines(pipelines) do
      {:ok, count}
    end
  end

  defp split_documents(content) do
    if String.contains?(content, "\n---\n") do
      String.split(content, "\n---\n")
    else
      [content]
    end
  end

  # Parse JSON first, fall back to YAML.
  defp parse_content(content) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> parse_yaml(content)
    end
  end

  defp parse_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "unable to parse content as JSON or YAML: #{inspect(reason)}"}
    end
  end

  # ── Pipeline extraction (JSON array format) ──────────────────────────

  defp extract_pipelines(%{"pipelines" => pipelines}) when is_list(pipelines) do
    {:ok, pipelines}
  end

  # ── GoCD YAML format: pipelines are named entries in a map ───────────

  defp extract_pipelines(%{"pipelines" => pipelines}) when is_map(pipelines) do
    normalized =
      Enum.map(pipelines, fn {name, config} ->
        normalize_gocd_pipeline(name, config)
      end)

    {:ok, normalized}
  end

  defp extract_pipelines(%{"pipeline" => pipeline}) do
    {:ok, [pipeline]}
  end

  defp extract_pipelines(pipelines) when is_list(pipelines) do
    {:ok, pipelines}
  end

  defp extract_pipelines(_) do
    {:error, "no pipelines found in config file"}
  end

  # ── GoCD YAML normalization ──────────────────────────────────────────

  defp normalize_gocd_pipeline(name, config) when is_map(config) do
    %{
      "name" => name,
      "group" => Map.get(config, "group", "default"),
      "label_template" => config["label_template"] || "${COUNT}",
      "lock_behavior" => normalize_lock_behavior(config["locking"]),
      "parameters" => config["parameters"] || config["params"] || %{},
      "timer" => config["timer"],
      "timer_only_on_changes" => config["timer_only_on_changes"] || false,
      "materials" => normalize_gocd_materials(config["materials"]),
      "environment_variables" => config["environment_variables"] || %{},
      "stages" => normalize_gocd_stages(config["stages"] || [])
    }
  end

  defp normalize_lock_behavior("off"), do: "none"
  defp normalize_lock_behavior("on"), do: "lockOnFailure"
  defp normalize_lock_behavior(nil), do: "none"
  defp normalize_lock_behavior(other), do: other

  # GoCD YAML materials: {name: {git: url, branch: ...}} → [{type, url, branch, name}]
  defp normalize_gocd_materials(nil), do: []
  defp normalize_gocd_materials(materials) when is_list(materials), do: materials

  defp normalize_gocd_materials(materials) when is_map(materials) do
    Enum.map(materials, fn {mat_name, mat_config} ->
      {type, url} = extract_gocd_material_type_url(mat_config)

      %{
        "type" => type,
        "url" => url,
        "branch" => mat_config["branch"] || "master",
        "name" => mat_name,
        "auto_update" => Map.get(mat_config, "auto_update", true)
      }
    end)
  end

  defp extract_gocd_material_type_url(mat_config) do
    cond do
      Map.has_key?(mat_config, "git") -> {"git", mat_config["git"]}
      Map.has_key?(mat_config, "svn") -> {"svn", mat_config["svn"]}
      Map.has_key?(mat_config, "hg") -> {"hg", mat_config["hg"]}
      Map.has_key?(mat_config, "pipeline") -> {"dependency", mat_config["pipeline"]}
      true -> {"git", mat_config["url"] || ""}
    end
  end

  # GoCD YAML stages: [{stage_name: {jobs: {job_name: {...}}}}]
  defp normalize_gocd_stages(stages) when is_list(stages) do
    Enum.map(stages, fn
      stage when is_map(stage) ->
        # Already in JSON array format? Check if it has "name" key
        if Map.has_key?(stage, "name") do
          stage
        else
          # GoCD YAML format: single-key map {stage_name: config}
          [{stage_name, stage_config}] = Map.to_list(stage)

          %{
            "name" => stage_name,
            "approval_type" => stage_config["approval"] || "success",
            "fetch_materials" => Map.get(stage_config, "fetch_materials", true),
            "clean_working_directory" =>
              Map.get(stage_config, "clean_workspace", false) || Map.get(stage_config, "clean_working_directory", false),
            "never_cleanup_artifacts" =>
              Map.get(stage_config, "never_cleanup_artifacts", false),
            "artifact_retention_runs" =>
              Map.get(stage_config, "artifact_retention_runs", 1),
            "environment_variables" => stage_config["environment_variables"] || %{},
            "jobs" => normalize_gocd_jobs(stage_config["jobs"] || %{})
          }
        end

      other ->
        other
    end)
  end

  # GoCD YAML jobs: {job_name: {resources, tasks, ...}}
  defp normalize_gocd_jobs(jobs) when is_list(jobs), do: jobs

  defp normalize_gocd_jobs(jobs) when is_map(jobs) do
    Enum.map(jobs, fn {job_name, job_config} ->
      %{
        "name" => job_name,
        "resources" => job_config["resources"] || [],
        "run_on_all_agents" => normalize_run_instances(job_config["run_instances"]),
        "run_instance_count" => job_config["run_instance_count"],
        "environment_variables" => job_config["environment_variables"] || %{},
        "timeout" => job_config["timeout"],
        "tasks" => normalize_gocd_tasks(job_config["tasks"] || [])
      }
    end)
  end

  defp normalize_run_instances("all"), do: true
  defp normalize_run_instances(nil), do: false
  defp normalize_run_instances(_), do: false

  # GoCD YAML tasks: [{exec: {command, arguments}}] → [{type: "exec", command, arguments}]
  defp normalize_gocd_tasks(tasks) when is_list(tasks) do
    Enum.map(tasks, fn
      task when is_map(task) ->
        if Map.has_key?(task, "type") do
          task
        else
          # GoCD YAML format: {exec|fetch|ant|...: config}
          [{task_type, task_config}] = Map.to_list(task)

          %{
            "type" => task_type,
            "command" => task_config["command"],
            "arguments" => task_config["arguments"] || [],
            "working_directory" => task_config["working_directory"],
            "run_if" => task_config["run_if"] || "passed"
          }
        end

      other ->
        other
    end)
  end

  defp upsert_pipelines(pipelines) do
    count =
      Enum.reduce(pipelines, 0, fn pipeline_def, acc ->
        upsert_single_pipeline(pipeline_def)
        acc + 1
      end)

    {:ok, count}
  end

  defp upsert_single_pipeline(pipeline_def) when is_map(pipeline_def) do
    name = pipeline_def["name"] || raise("pipeline name is required")
    group = pipeline_def["group"] || "default"

    attrs = %{
      name: name,
      group: group,
      label_template: pipeline_def["label_template"] || "${COUNT}",
      lock_behavior: pipeline_def["lock_behavior"] || "none",
      parameters: pipeline_def["parameters"] || %{},
      timer: pipeline_def["timer"],
      timer_only_on_changes: pipeline_def["timer_only_on_changes"] || false
    }

    result =
      case Pipelines.get_pipeline_by_name(name) do
        nil ->
          # Create new pipeline with stages
          {:ok, pipeline} = create_pipeline_with_stages(attrs, pipeline_def)
          pipeline

        existing ->
          # Update existing — for now just update attrs, stages handled separately
          existing
          |> ExGoCD.Pipelines.Pipeline.changeset(attrs)
          |> Repo.update()
          |> case do
            {:ok, pipeline} -> pipeline
            {:error, _} -> existing
          end
      end

    # Upsert materials
    upsert_materials(result, pipeline_def)

    # Upsert stages
    upsert_stages(result, pipeline_def["stages"] || [])

    :ok
  end

  defp create_pipeline_with_stages(attrs, pipeline_def) do
    alias ExGoCD.Pipelines.Pipeline

    {:ok, pipeline} =
      %Pipeline{}
      |> Pipeline.changeset(attrs)
      |> Repo.insert()

    upsert_materials(pipeline, pipeline_def)
    upsert_stages(pipeline, pipeline_def["stages"] || [])

    {:ok, pipeline}
  end

  defp upsert_materials(pipeline, pipeline_def) do
    materials = pipeline_def["materials"] || pipeline_def[:materials] || []

    Enum.each(materials, fn mat ->
      mat_type = mat["type"] || "git"

      mat_attrs = %{
        type: mat_type,
        url: mat["url"],
        branch: mat["branch"] || "main",
        username: mat["username"],
        destination: mat["destination"],
        auto_update: Map.get(mat, "auto_update", true)
      }

      # Check if this material already exists for this pipeline
      existing_mats = Repo.preload(pipeline, :materials).materials || []
      exists? = Enum.any?(existing_mats, &(&1.url == mat_attrs.url && &1.type == mat_attrs.type))

      unless exists? do
        case Repo.get_by(ExGoCD.Pipelines.Material, url: mat_attrs.url, type: mat_attrs.type) do
          nil ->
            link_new_material(mat_attrs, pipeline.id, existing_mats)

          material ->
            link_existing_material(material, existing_mats, pipeline.id)
        end
      end
    end)
  end

  defp link_new_material(mat_attrs, pipeline_id, _existing_mats) do
    {:ok, material} =
      %ExGoCD.Pipelines.Material{}
      |> ExGoCD.Pipelines.Material.changeset(mat_attrs)
      |> Repo.insert()

    Repo.insert_all("pipelines_materials", [
      %{
        pipeline_id: pipeline_id,
        material_id: material.id
      }
    ])
  end

  defp link_existing_material(material, existing_mats, pipeline_id) do
    unless Enum.any?(existing_mats, &(&1.id == material.id)) do
      Repo.insert_all("pipelines_materials", [
        %{
          pipeline_id: pipeline_id,
          material_id: material.id
        }
      ])
    end
  end

  defp upsert_stages(pipeline, stage_defs) when is_list(stage_defs) do
    existing_stages = Repo.preload(pipeline, stages: [jobs: :tasks]).stages || []

    Enum.each(stage_defs, fn stage_def ->
      stage = find_or_create_stage(stage_def, existing_stages, pipeline.id)
      upsert_jobs(stage, stage_def["jobs"] || [])
    end)
  end

  defp find_or_create_stage(stage_def, existing_stages, pipeline_id) do
    stage_name = stage_def["name"]

    stage_attrs = %{
      name: stage_name,
      pipeline_id: pipeline_id,
      approval_type: stage_def["approval_type"] || "success",
      fetch_materials: Map.get(stage_def, "fetch_materials", true),
      clean_working_directory: Map.get(stage_def, "clean_working_directory", false),
      never_cleanup_artifacts: Map.get(stage_def, "never_cleanup_artifacts", false),
      artifact_retention_runs: Map.get(stage_def, "artifact_retention_runs", 1),
      environment_variables: stage_def["environment_variables"] || %{}
    }

    case Enum.find(existing_stages, &(&1.name == stage_name)) do
      nil ->
        {:ok, new_stage} =
          %ExGoCD.Pipelines.Stage{}
          |> ExGoCD.Pipelines.Stage.changeset(stage_attrs)
          |> Repo.insert()

        new_stage

      existing ->
        existing
        |> ExGoCD.Pipelines.Stage.changeset(stage_attrs)
        |> Repo.update!()

        existing
    end
  end

  defp upsert_jobs(stage, job_defs) when is_list(job_defs) do
    existing_jobs = Repo.preload(stage, jobs: :tasks).jobs || []

    Enum.each(job_defs, fn job_def ->
      job = find_or_create_job(job_def, existing_jobs, stage.id)
      upsert_tasks(job, job_def["tasks"] || [])
    end)
  end

  defp find_or_create_job(job_def, existing_jobs, stage_id) do
    job_name = job_def["name"]

    job_attrs = %{
      name: job_name,
      stage_id: stage_id,
      resources: job_def["resources"] || [],
      run_on_all_agents: job_def["run_on_all_agents"] || false,
      environment_variables: job_def["environment_variables"] || %{},
      timeout: job_def["timeout"],
      run_instance_count: job_def["run_instance_count"]
    }

    case Enum.find(existing_jobs, &(&1.name == job_name)) do
      nil ->
        {:ok, new_job} =
          %ExGoCD.Pipelines.Job{}
          |> ExGoCD.Pipelines.Job.changeset(job_attrs)
          |> Repo.insert()

        new_job

      existing ->
        existing
        |> ExGoCD.Pipelines.Job.changeset(job_attrs)
        |> Repo.update!()

        existing
    end
  end

  defp upsert_tasks(job, task_defs) when is_list(task_defs) do
    existing_tasks = Repo.preload(job, :tasks).tasks || []

    Enum.each(task_defs, fn task_def ->
      _task_name = task_def["name"] || task_def["type"]

      task_attrs = %{
        type: task_def["type"] || "exec",
        command: task_def["command"],
        arguments: task_def["arguments"] || [],
        working_directory: task_def["working_directory"],
        run_if: task_def["run_if"] || "passed"
      }

      unless Enum.any?(
               existing_tasks,
               &(&1.type == task_attrs.type && &1.command == task_attrs.command)
             ) do
        %ExGoCD.Pipelines.Task{}
        |> ExGoCD.Pipelines.Task.changeset(Map.put(task_attrs, :job_id, job.id))
        |> Repo.insert()
      end
    end)
  end
end
