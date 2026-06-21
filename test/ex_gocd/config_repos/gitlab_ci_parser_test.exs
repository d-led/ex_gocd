defmodule ExGoCD.ConfigRepos.GitLabCIParserTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.ConfigRepos.GitLabCIParser

  @fixture_simple ~s"""
  stages:
    - build
    - test
  variables:
    DEPLOY_ENV: staging
  build-job:
    stage: build
    script:
      - make build
  test-job:
    stage: test
    needs:
      - build-job
    script:
      - make test
    tags:
      - docker
  """

  @fixture_with_includes ~s"""
  include:
    - local: ci/build.gitlab-ci.yml
  stages:
    - build
    - test
  test-job:
    stage: test
    script: echo "testing"
  """

  @fixture_with_rules ~s"""
  stages:
    - deploy
  deploy-prod:
    stage: deploy
    script: ./deploy.sh
    rules:
      - if: $CI_COMMIT_BRANCH == "main"
      - if: $CI_COMMIT_TAG
        when: manual
  """

  describe "parse_gitlab_ci/2" do
    test "parses simple pipeline with stages and jobs" do
      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(@fixture_simple, ".gitlab-ci.yml")

      assert ir.source_type == "gitlab_ci"
      assert ir.source_file == ".gitlab-ci.yml"
      assert ir.stages == ["build", "test"]
      assert ir.env_vars == %{"DEPLOY_ENV" => "staging"}
      assert map_size(ir.jobs) == 2

      build = ir.jobs["build-job"]
      assert build.stage == "build"
      assert build.needs == []
      assert length(build.steps) == 1
      assert hd(build.steps).type == "script"
      assert hd(build.steps).command == "make build"

      test_job = ir.jobs["test-job"]
      assert test_job.stage == "test"
      assert test_job.needs == ["build-job"]
      assert test_job.tags == ["docker"]
    end

    test "emits include paths in IR" do
      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(@fixture_with_includes, ".gitlab-ci.yml")

      assert ir.includes == ["ci/build.gitlab-ci.yml"]
    end

    test "parses rules with if conditions" do
      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(@fixture_with_rules, ".gitlab-ci.yml")

      deploy = ir.jobs["deploy-prod"]
      assert deploy.stage == "deploy"
      assert length(deploy.rules) == 2
      assert hd(deploy.rules).if == ~s($CI_COMMIT_BRANCH == "main")
      assert List.last(deploy.rules).when == "manual"
    end

    test "extracts before_script and after_script as separate steps" do
      yaml = ~s"""
      stages:
        - build
      build:
        stage: build
        before_script:
          - echo setup
        script:
          - make build
        after_script:
          - echo cleanup
      """

      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(yaml, ".gitlab-ci.yml")

      build = ir.jobs["build"]
      assert length(build.steps) == 3
      assert Enum.at(build.steps, 0).type == "before_script"
      assert Enum.at(build.steps, 1).type == "script"
      assert Enum.at(build.steps, 2).type == "after_script"
    end

    test "parses when: manual jobs" do
      yaml = ~s"""
      stages:
        - deploy
      deploy:
        stage: deploy
        script: ./deploy.sh
        when: manual
      """

      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(yaml, ".gitlab-ci.yml")

      assert ir.jobs["deploy"].when == "manual"
    end

    test "uses project name when no pipeline name available" do
      {:ok, ir} = GitLabCIParser.parse_gitlab_ci(@fixture_simple, ".gitlab-ci.yml")

      assert ir.name == "gitlab-ci"
    end

    test "returns error for invalid YAML" do
      assert {:error, reason} = GitLabCIParser.parse_gitlab_ci(": : :", "broken.yml")
      assert reason =~ ~r/parse|invalid/i
    end
  end
end
