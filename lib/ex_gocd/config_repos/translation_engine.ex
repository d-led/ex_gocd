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

  defp create_pipeline_from_attrs(attrs) do
    Repo.transaction(fn ->
      {:ok, pipeline} =
        %Pipelines.Pipeline{}
        |> Pipelines.Pipeline.changeset(
          Map.take(attrs, [
            :name,
            :group,
            :label_template,
            :environment_variables,
            :timer,
            :config_repo_id,
            :source_file_path
          ])
        )
        |> Repo.insert()

      # Upsert materials
      Enum.each(attrs[:materials] || [], fn mat ->
        {:ok, material} =
          %Pipelines.Material{}
          |> Pipelines.Material.changeset(mat)
          |> Repo.insert()

        Repo.insert_all("pipelines_materials", [
          %{
            pipeline_id: pipeline.id,
            material_id: material.id
          }
        ])
      end)

      # Create stages with jobs and tasks
      Enum.each(attrs[:stages] || [], fn stage_attrs ->
        {:ok, stage} =
          %Pipelines.Stage{}
          |> Pipelines.Stage.changeset(Map.put(stage_attrs, :pipeline_id, pipeline.id))
          |> Repo.insert()

        create_jobs_for_stage(stage, stage_attrs)
      end)

      {:ok, pipeline}
    end)
  end

  defp create_jobs_for_stage(stage, stage_attrs) do
    Enum.each(stage_attrs[:jobs] || [], fn job_attrs ->
      {:ok, job} =
        %Pipelines.Job{}
        |> Pipelines.Job.changeset(
          Map.merge(job_attrs, %{stage_id: stage.id})
          |> Map.drop([:tasks, :resources])
        )
        |> Ecto.Changeset.put_change(:resources, job_attrs[:resources] || [])
        |> Repo.insert()

      create_tasks_for_job(job, job_attrs)
    end)
  end

  defp create_tasks_for_job(job, job_attrs) do
    Enum.each(job_attrs[:tasks] || [], fn task_attrs ->
      {:ok, _task} =
        %Pipelines.Task{}
        |> Pipelines.Task.changeset(Map.put(task_attrs, :job_id, job.id))
        |> Repo.insert()
    end)
  end

  defp update_pipeline_from_attrs(existing, attrs) do
    # For now, just update basic attrs. Full upsert of stages/jobs is more complex.
    # The config repo parser does this in a simpler way.
    existing
    |> Pipelines.Pipeline.changeset(
      Map.take(attrs, [:name, :group, :label_template, :environment_variables])
    )
    |> Repo.update()
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
