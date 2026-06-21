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
  Returns {:ok, count} with number of pipelines upserted, or {:error, reason}.
  """
  @spec parse_and_upsert(String.t()) :: {:ok, integer()} | {:error, String.t()}
  def parse_and_upsert(content) when is_binary(content) do
    with {:ok, parsed} <- parse_yaml(content),
         {:ok, pipelines} <- extract_pipelines(parsed),
         {:ok, count} <- upsert_pipelines(pipelines) do
      {:ok, count}
    end
  end

  # Parse JSON content. YAML support can be added later with yaml_elixir dep.
  defp parse_yaml(content) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, "unable to parse content as JSON (YAML support requires yaml_elixir dependency)"}
    end
  end

  defp extract_pipelines(%{"pipelines" => pipelines}) when is_list(pipelines) do
    {:ok, pipelines}
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

    Repo.insert_all("pipelines_materials", [%{
      pipeline_id: pipeline_id,
      material_id: material.id
    }])
  end

  defp link_existing_material(material, existing_mats, pipeline_id) do
    unless Enum.any?(existing_mats, &(&1.id == material.id)) do
      Repo.insert_all("pipelines_materials", [%{
        pipeline_id: pipeline_id,
        material_id: material.id
      }])
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

      unless Enum.any?(existing_tasks, &(&1.type == task_attrs.type && &1.command == task_attrs.command)) do
        %ExGoCD.Pipelines.Task{}
        |> ExGoCD.Pipelines.Task.changeset(Map.put(task_attrs, :job_id, job.id))
        |> Repo.insert()
      end
    end)
  end
end
