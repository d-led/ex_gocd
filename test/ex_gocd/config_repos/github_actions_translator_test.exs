defmodule ExGoCD.ConfigRepos.GitHubActionsTranslatorTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.ConfigRepos.{ExternalPipelineIR, GitHubActionsTranslator, GitHubActionsParser}

  @prefix "eci-test-ghat"

  @fixture_ci ~s"""
  name: CI
  on:
    push:
      branches: [main]
  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - run: make build
    test:
      needs: [build]
      runs-on: ubuntu-latest
      steps:
        - run: make test
  """

  @fixture_dispatch ~s"""
  name: Release
  on:
    workflow_dispatch:
  jobs:
    publish:
      runs-on: ubuntu-latest
      steps:
        - run: npm publish
  """

  setup do
    prefix = "#{@prefix}-#{System.unique_integer([:positive])}"
    {:ok, prefix: prefix}
  end

  describe "translate/2 — translate mode" do
    test "translates a push-triggered workflow to pipeline attrs", %{prefix: prefix} do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_ci, ".github/workflows/ci.yml")
      name = "#{prefix}-CI"


      {:ok, attrs} = GitHubActionsTranslator.translate(ir, %{
        mode: "translate",
        pipeline_name_prefix: prefix
      })

      assert attrs.name == name
      assert attrs.group == prefix
      assert attrs.label_template == "${COUNT}"

      # Materials: git material with branch filter
      assert length(attrs.materials) == 1
      mat = hd(attrs.materials)
      assert mat.type == "git"
      assert mat.branch == "main"
      assert mat.auto_update == true

      # Stages: one per job
      assert length(attrs.stages) == 2
      build_stage = Enum.find(attrs.stages, &(&1.name == "build"))
      test_stage = Enum.find(attrs.stages, &(&1.name == "test"))
      assert build_stage
      assert test_stage
      assert test_stage.approval_type == "success"

      # Build stage has jobs
      assert length(build_stage.jobs) == 1
      build_job = hd(build_stage.jobs)
      assert build_job.name == "build"
      assert build_job.resources == ["ubuntu-latest"]

      # Build job has tasks
      assert length(build_job.tasks) == 1
      assert hd(build_job.tasks).type == "exec"
      assert hd(build_job.tasks).command == "make build"
    end

    test "workflow_dispatch creates pipeline with no material (manual trigger)", %{prefix: prefix} do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_dispatch, ".github/workflows/release.yml")

      {:ok, attrs} = GitHubActionsTranslator.translate(ir, %{
        mode: "translate",
        pipeline_name_prefix: prefix
      })

      assert attrs.materials == []
    end

    test "respects selected_jobs filter", %{prefix: prefix} do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_ci, ".github/workflows/ci.yml")

      {:ok, attrs} = GitHubActionsTranslator.translate(ir, %{
        mode: "translate",
        pipeline_name_prefix: prefix,
        selected_jobs: %{"included" => ["build"]}
      })

      assert length(attrs.stages) == 1
      assert hd(attrs.stages).name == "build"
    end

    test "skips workflow with uses: action steps when in translate mode (v1 behavior)", %{prefix: prefix} do
      yaml = ~s"""
      name: Deploy
      on: push
      jobs:
        deploy:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v4
            - run: ./deploy.sh
      """
      {:ok, ir} = GitHubActionsParser.parse_workflow(yaml, ".github/workflows/deploy.yml")

      {:ok, attrs} = GitHubActionsTranslator.translate(ir, %{mode: "translate", pipeline_name_prefix: prefix})

      # The action step (checkout) is skipped, only the run step remains
      deploy_stage = hd(attrs.stages)
      deploy_job = hd(deploy_stage.jobs)
      assert length(deploy_job.tasks) == 1
      assert hd(deploy_job.tasks).command == "./deploy.sh"
    end
  end

  describe "translate/2 — execute mode" do
    test "creates an external task pipeline for execute_act mode", %{prefix: prefix} do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_ci, ".github/workflows/ci.yml")

      {:ok, attrs} = GitHubActionsTranslator.translate(ir, %{
        mode: "execute_act",
        pipeline_name_prefix: prefix,
        selected_jobs: %{"included" => ["build"]}
      })

      # Single stage, single job, single external task
      assert length(attrs.stages) == 1
      assert hd(attrs.stages).name == "build"
      jobs = hd(attrs.stages).jobs
      assert length(jobs) == 1

      tasks = hd(jobs).tasks
      assert length(tasks) == 1
      task = hd(tasks)
      assert task.type == "external"
      assert task.external_config.executor == "act"
      assert task.external_config.job_name == "build"
    end
  end

  describe "translate/2 — skip mode" do
    test "returns empty stages for skip mode", %{prefix: prefix} do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_ci, ".github/workflows/ci.yml")

      {:ok, attrs} = GitHubActionsTranslator.translate(ir, %{
        mode: "skip",
        pipeline_name_prefix: prefix
      })

      assert attrs.name =~ prefix
      assert attrs.stages == []
    end
  end
end
