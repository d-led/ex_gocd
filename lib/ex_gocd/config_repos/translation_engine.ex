defmodule ExGoCD.ConfigRepos.TranslationEngine do
  @moduledoc """
  Orchestrates translation of ExternalPipelineIR structs into persisted GoCD pipelines.

  Reads `ConfigRepoFileSelection` records to determine mode, selected jobs, and
  overrides. Delegates to the appropriate translator (GH Actions or GitLab CI).

  Also handles change detection via `sync_changes/1`.
  """

  alias ExGoCD.ConfigRepos.{
    ConfigRepoFile,
    ConfigRepoFileSelection,
    ExternalPipelineIR,
    GitHubActionsParser,
    GitHubActionsTranslator,
    GitLabCIParser,
    GitLabCITranslator
  }

  alias ExGoCD.{Pipelines, Repo}
  import Ecto.Query

  @doc """
  Translates and persists pipelines from a single IR with selections.

  Returns `{:ok, pipeline_count}` or `{:error, reason}`.
  """
  @spec translate_and_persist(ExternalPipelineIR.t(), map()) ::
          {:ok, integer()} | {:error, String.t()}
  def translate_and_persist(ir, selections) do
    mode = Map.get(selections, :mode, "translate")

    if mode == "skip" do
      {:ok, 0}
    else
      with {:ok, attrs} <- translate(ir, selections),
           {:ok, _pipeline} <- persist_pipeline(attrs) do
        {:ok, 1}
      end
    end
  end

  @doc """
  Translates and persists all pipelines for a config repo from its file selections.
  Each file's IR is translated according to its selection record.

  Returns `{:ok, count}` with number of pipelines upserted.
  """
  @spec translate_and_persist_all(integer()) :: {:ok, integer()} | {:error, String.t()}
  def translate_and_persist_all(config_repo_id) when is_integer(config_repo_id) do
    files = list_files_with_selections(config_repo_id)

    results =
      Enum.reduce_while(files, {:ok, 0}, fn {file, selection}, {:ok, acc} ->
        with {:ok, content} <- get_file_content(file),
             {:ok, ir} <- parse_content(content, file),
             {:ok, count} <- translate_and_persist(ir, selection_to_map(selection)) do
          {:cont, {:ok, acc + count}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    results
  end

  # --- Private ---

  defp translate(ir, selections) do
    case ir.source_type do
      "github_actions" -> GitHubActionsTranslator.translate(ir, selections)
      "gitlab_ci" -> GitLabCITranslator.translate(ir, selections)
      _ -> {:error, "unsupported source_type: #{ir.source_type}"}
    end
  end

  defp persist_pipeline(attrs) do
    case Pipelines.get_pipeline_by_name(attrs.name) do
      nil ->
        create_pipeline_from_attrs(attrs)

      existing ->
        update_pipeline_from_attrs(existing, attrs)
    end
  end

  @pipeline_fields [
    :name,
    :group,
    :label_template,
    :environment_variables,
    :timer,
    :config_repo_id,
    :source_file_path
  ]

  @stage_fields [
    :name,
    :approval_type,
    :fetch_materials,
    :clean_working_directory,
    :never_cleanup_artifacts,
    :artifact_retention_runs,
    :environment_variables
  ]

  @job_fields [
    :name,
    :run_instance_count,
    :timeout,
    :environment_variables,
    :run_on_all_agents,
    :elastic_profile_id,
    :tabs,
    :artifact_configs
  ]

  defp create_pipeline_from_attrs(attrs) do
    Repo.transaction(fn ->
      {:ok, pipeline} =
        %Pipelines.Pipeline{}
        |> Pipelines.Pipeline.changeset(Map.take(attrs, @pipeline_fields))
        |> Repo.insert()

      insert_materials(pipeline, attrs[:materials] || [])
      upsert_stages(pipeline, attrs[:stages] || [])

      pipeline
    end)
  end

  # The repository is translated again whenever it changes, so a pipeline that
  # is already there is written the way it is created: by name, without
  # replacing rows. A stage or job's row is what its run history points at, so
  # one the workflow still names keeps the row it had.
  defp update_pipeline_from_attrs(existing, attrs) do
    Repo.transaction(fn ->
      {:ok, pipeline} =
        existing
        |> Pipelines.Pipeline.changeset(Map.take(attrs, @pipeline_fields))
        |> Repo.update()

      upsert_stages(pipeline, attrs[:stages] || [])

      pipeline
    end)
  end

  defp insert_materials(pipeline, materials) do
    Enum.each(materials, fn material_attrs ->
      {:ok, material} =
        %Pipelines.Material{}
        |> Pipelines.Material.changeset(material_attrs)
        |> Repo.insert()

      Repo.insert_all("pipelines_materials", [
        %{pipeline_id: pipeline.id, material_id: material.id}
      ])
    end)
  end

  defp upsert_stages(pipeline, stage_attrs_list) do
    Enum.each(stage_attrs_list, fn stage_attrs ->
      stage = upsert_stage(pipeline, stage_attrs)
      upsert_jobs(stage, stage_attrs[:jobs] || [])
    end)
  end

  defp upsert_stage(pipeline, stage_attrs) do
    attrs =
      stage_attrs
      |> Map.take(@stage_fields)
      |> Map.put(:pipeline_id, pipeline.id)

    case Repo.get_by(Pipelines.Stage, pipeline_id: pipeline.id, name: attrs[:name]) do
      nil -> insert!(Pipelines.Stage, attrs)
      existing -> update!(Pipelines.Stage, existing, attrs)
    end
  end

  defp upsert_jobs(stage, job_attrs_list) do
    Enum.each(job_attrs_list, fn job_attrs ->
      job = upsert_job(stage, job_attrs)
      replace_tasks(job, job_attrs[:tasks] || [])
    end)
  end

  defp upsert_job(stage, job_attrs) do
    attrs =
      job_attrs
      |> Map.take(@job_fields)
      |> Map.put(:stage_id, stage.id)
      |> Map.put(:resources, job_attrs[:resources] || [])

    case Repo.get_by(Pipelines.Job, stage_id: stage.id, name: attrs[:name]) do
      nil -> insert!(Pipelines.Job, attrs)
      existing -> update!(Pipelines.Job, existing, attrs)
    end
  end

  # A task has nothing to be found by and nothing points at it, so the list the
  # workflow gives is the list the job has.
  defp replace_tasks(job, task_attrs_list) do
    Repo.delete_all(from t in Pipelines.Task, where: t.job_id == ^job.id)

    Enum.each(task_attrs_list, fn task_attrs ->
      insert!(Pipelines.Task, Map.put(task_attrs, :job_id, job.id))
    end)
  end

  defp insert!(schema, attrs) do
    {:ok, row} = schema |> struct() |> schema.changeset(attrs) |> Repo.insert()
    row
  end

  defp update!(schema, row, attrs) do
    {:ok, row} = schema.changeset(row, attrs) |> Repo.update()
    row
  end

  defp list_files_with_selections(config_repo_id) do
    files = Repo.all(from f in ConfigRepoFile, where: f.config_repo_id == ^config_repo_id)

    Enum.map(files, fn file ->
      selection =
        Repo.one(from s in ConfigRepoFileSelection, where: s.config_repo_file_id == ^file.id)

      {file, selection}
    end)
  end

  defp get_file_content(file) do
    if file.raw_content do
      {:ok, file.raw_content}
    else
      {:error, "no cached content for #{file.path}"}
    end
  end

  defp parse_content(content, file) do
    case file.source_type do
      "github_workflow" -> GitHubActionsParser.parse_workflow(content, file.path)
      "gitlab_pipeline" -> GitLabCIParser.parse_gitlab_ci(content, file.path)
      "gitlab_include" -> {:error, "include files are not translated independently"}
      _ -> {:error, "unsupported file source_type: #{file.source_type}"}
    end
  end

  defp selection_to_map(nil), do: %{mode: "translate"}

  defp selection_to_map(selection) do
    %{
      mode: selection.mode || "translate",
      selected_jobs: selection.selected_jobs,
      selected_triggers: selection.selected_triggers,
      overrides: selection.overrides || %{}
    }
  end
end
