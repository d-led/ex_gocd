defmodule ExGoCD.ConfigRepos.GitLabCITranslatorTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.ConfigRepos.{GitLabCITranslator, GitLabCIParser}

  @prefix "eci-test-glct"

  @fixture_simple ~s"""
  stages:
    - build
    - test
  variables:
    DEPLOY_ENV: staging
  build-job:
    stage: build
    script: make build
  test-job:
    stage: test
    needs:
      - build-job
    script: make test
    tags:
      - docker
  """

  setup do
    prefix = "#{@prefix}-#{System.unique_integer([:positive])}"
    {:ok, prefix: prefix}
  end

  describe "translate/2 — translate mode" do
    test "translates a simple GitLab CI to pipeline attrs", %{prefix: prefix} do
      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(@fixture_simple, ".gitlab-ci.yml")

      {:ok, attrs} =
        GitLabCITranslator.translate(ir, %{
          mode: "translate",
          pipeline_name_prefix: prefix
        })

      assert attrs.name == "#{prefix}-gitlab-ci"
      assert attrs.group == prefix
      assert attrs.environment_variables == %{"DEPLOY_ENV" => "staging"}

      # Stages ordered by GitLab stages list
      assert length(attrs.stages) == 2
      assert hd(attrs.stages).name == "build"
      build_stage = hd(attrs.stages)
      test_stage = List.last(attrs.stages)
      assert test_stage.name == "test"
      assert test_stage.approval_type == "success"

      # Build stage
      build_job = hd(build_stage.jobs)
      assert build_job.name == "build-job"
      assert build_job.tasks |> hd() |> Map.get(:command) == "make build"

      # Test stage with tags → resources
      test_job = hd(test_stage.jobs)
      assert test_job.name == "test-job"
      assert test_job.resources == ["docker"]
    end

    test "respects selected_jobs filter", %{prefix: prefix} do
      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(@fixture_simple, ".gitlab-ci.yml")

      {:ok, attrs} =
        GitLabCITranslator.translate(ir, %{
          mode: "translate",
          pipeline_name_prefix: prefix,
          selected_jobs: %{"included" => ["build-job"]}
        })

      assert length(attrs.stages) == 1
      assert hd(attrs.stages).name == "build"
    end

    test "handles when: manual jobs with approval_type manual", %{prefix: prefix} do
      yaml = ~s"""
      stages:
        - deploy
      deploy:
        stage: deploy
        script: ./deploy.sh
        when: manual
      """

      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(yaml, ".gitlab-ci.yml")

      {:ok, attrs} =
        GitLabCITranslator.translate(ir, %{mode: "translate", pipeline_name_prefix: prefix})

      assert hd(attrs.stages).approval_type == "manual"
    end
  end

  describe "translate/2 — skip mode" do
    test "returns empty stages for skip", %{prefix: prefix} do
      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(@fixture_simple, ".gitlab-ci.yml")

      {:ok, attrs} =
        GitLabCITranslator.translate(ir, %{mode: "skip", pipeline_name_prefix: prefix})

      assert attrs.stages == []
    end
  end
end
