defmodule ExGoCD.ConfigRepos.GitHubActionsParserTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.ConfigRepos.GitHubActionsParser

  @fixture_simple ~s"""
  name: CI
  on:
    push:
      branches: [main]
  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - run: echo "building"
        - run: make test
    deploy:
      needs: [build]
      runs-on: ubuntu-latest
      steps:
        - run: echo "deploying"
  """

  @fixture_schedule ~s"""
  name: Nightly
  on:
    schedule:
      - cron: '0 2 * * *'
  jobs:
    cleanup:
      runs-on: ubuntu-latest
      steps:
        - run: rm -rf tmp/
  """

  @fixture_dispatch ~s"""
  name: Release
  on:
    workflow_dispatch:
      inputs:
        version:
          description: 'Version to release'
          required: true
  jobs:
    publish:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - run: npm publish
  """

  describe "parse_workflow/2" do
    test "parses simple push-triggered workflow" do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_simple, ".github/workflows/ci.yml")

      assert ir.source_type == "github_actions"
      assert ir.source_file == ".github/workflows/ci.yml"
      assert ir.name == "CI"
      assert ir.stages == ["build", "deploy"]
      assert map_size(ir.jobs) == 2

      # build job
      build = ir.jobs["build"]
      assert build.stage == "build"
      assert build.needs == []
      assert build.runs_on == "ubuntu-latest"
      assert length(build.steps) == 2
      assert hd(build.steps).type == "run"
      assert hd(build.steps).command == ~s(echo "building")

      # deploy job
      deploy = ir.jobs["deploy"]
      assert deploy.stage == "deploy"
      assert deploy.needs == ["build"]

      # triggers
      assert length(ir.triggers) == 1
      assert hd(ir.triggers).type == "push"
      assert hd(ir.triggers).branches == ["main"]
    end

    test "parses schedule trigger" do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_schedule, ".github/workflows/nightly.yml")

      assert ir.name == "Nightly"
      assert length(ir.triggers) == 1
      assert hd(ir.triggers).type == "schedule"
      assert hd(ir.triggers).cron == "0 2 * * *"
    end

    test "parses workflow_dispatch trigger" do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_dispatch, ".github/workflows/release.yml")

      assert ir.name == "Release"
      assert length(ir.triggers) == 1
      assert hd(ir.triggers).type == "workflow_dispatch"

      # has inputs metadata
      trigger = hd(ir.triggers)
      assert trigger.inputs == %{"version" => %{"description" => "Version to release", "required" => true}}
    end

    test "records uses: steps with warning (v1 behavior)" do
      {:ok, ir} = GitHubActionsParser.parse_workflow(@fixture_dispatch, ".github/workflows/release.yml")

      publish = ir.jobs["publish"]
      assert length(publish.steps) == 2
      action_step = hd(publish.steps)
      assert action_step.type == "action"
      assert action_step.uses == "actions/checkout@v4"
    end

    test "returns error for invalid YAML" do
      assert {:error, reason} = GitHubActionsParser.parse_workflow(": : :", "broken.yml")
      assert reason =~ ~r/parse|invalid/i
    end

    test "returns error when parsed content is not a map" do
      # YAML parses to a list — returns error for non-map
      assert {:error, _} = GitHubActionsParser.parse_workflow("- just: a list", "list.yml")
      assert {:error, _} = GitHubActionsParser.parse_workflow("just a string", "string.yml")
    end

    test "uses workflow file name as name when no name key present" do
      yaml = ~s"""
      on: push
      jobs:
        test:
          runs-on: ubuntu-latest
          steps:
            - run: echo ok
      """

      {:ok, ir} = GitHubActionsParser.parse_workflow(yaml, ".github/workflows/unnamed.yml")

      # No explicit name, uses file stem
      assert ir.name == "unnamed"
    end
  end
end
