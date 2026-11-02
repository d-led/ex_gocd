defmodule ExGoCD.ConfigRepos.TranslationEngineTest do
  @moduledoc """
  The parsers and translators are tested on their own; this is the piece that
  puts them together with the database — a cached workflow file and its selection
  become a pipeline with the stages, jobs and tasks a person then sees in the UI.

  A pipeline from a config repository is re-translated whenever the repository
  changes, so translating the same file again has to update what is there rather
  than leave two pipelines with one name.
  """
  use ExGoCD.DataCase, async: true

  import Ecto.Query

  alias ExGoCD.ConfigRepos.{
    ConfigRepo,
    ConfigRepoFile,
    ConfigRepoFileSelection,
    TranslationEngine
  }

  alias ExGoCD.{Pipelines, Repo}

  @workflow ~s"""
  name: CI
  on:
    push:
      branches: [main]
  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - run: make build
  """

  setup do
    {:ok, repo} =
      Repo.insert(%ConfigRepo{
        url: "https://example.com/ci-config.git",
        branch: "main",
        material_type: "git",
        source_type: "gocd_pipeline"
      })

    %{repo: repo}
  end

  describe "translating a config repo" do
    test "turns a workflow file into a pipeline with its stage, job and task", %{repo: repo} do
      file = cached_workflow(repo, mode: "translate")

      assert {:ok, 1} = TranslationEngine.translate_and_persist_all(repo.id)

      pipeline = pipeline_from(file)
      assert pipeline.name == "CI"

      [stage] = Repo.preload(pipeline, stages: [jobs: :tasks]).stages
      assert stage.name == "build"

      [job] = stage.jobs
      [task] = job.tasks
      assert task.command =~ "make build"
    end

    test "translating the same file again leaves one pipeline, not two", %{repo: repo} do
      file = cached_workflow(repo, mode: "translate")

      assert {:ok, 1} = TranslationEngine.translate_and_persist_all(repo.id)
      assert {:ok, 1} = TranslationEngine.translate_and_persist_all(repo.id)

      assert Repo.aggregate(from(p in Pipelines.Pipeline, where: p.name == ^"CI"), :count) == 1
      assert pipeline_from(file).name == "CI"
    end

    test "a file set to be skipped makes no pipeline", %{repo: repo} do
      cached_workflow(repo, mode: "skip")

      assert {:ok, 0} = TranslationEngine.translate_and_persist_all(repo.id)
      assert Pipelines.get_pipeline_by_name("CI") == nil
    end

    test "a file whose content was never cached is reported, not guessed at", %{repo: repo} do
      {:ok, file} =
        Repo.insert(%ConfigRepoFile{
          config_repo_id: repo.id,
          path: ".github/workflows/ci.yml",
          source_type: "github_workflow",
          status: "new"
        })

      Repo.insert!(%ConfigRepoFileSelection{config_repo_file_id: file.id, mode: "translate"})

      assert {:error, reason} = TranslationEngine.translate_and_persist_all(repo.id)
      assert reason =~ "no cached content"
    end
  end

  defp cached_workflow(repo, mode: mode) do
    {:ok, file} =
      Repo.insert(%ConfigRepoFile{
        config_repo_id: repo.id,
        path: ".github/workflows/ci.yml",
        source_type: "github_workflow",
        status: "new",
        raw_content: @workflow
      })

    Repo.insert!(%ConfigRepoFileSelection{config_repo_file_id: file.id, mode: mode})
    file
  end

  defp pipeline_from(file) do
    pipeline = Pipelines.get_pipeline_by_name("CI")
    assert pipeline, "no pipeline was created for #{file.path}"
    pipeline
  end
end
