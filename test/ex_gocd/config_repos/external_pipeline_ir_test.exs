defmodule ExGoCD.ConfigRepos.ExternalPipelineIRTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.ConfigRepos.ExternalPipelineIR

  describe "new/1" do
    test "creates a GH Actions IR from valid attrs" do
      ir =
        ExternalPipelineIR.new(
          source_type: "github_actions",
          source_file: ".github/workflows/ci.yml",
          name: "CI",
          triggers: [%{type: "push", branches: ["main"]}],
          env_vars: %{"NODE_ENV" => "test"},
          stages: ["build", "test"],
          jobs: %{
            "build" => %{
              stage: "build",
              needs: [],
              runs_on: "ubuntu-latest",
              steps: [%{type: "run", command: "make build"}]
            },
            "test" => %{
              stage: "test",
              needs: ["build"],
              runs_on: "ubuntu-latest",
              steps: [%{type: "run", command: "make test"}]
            }
          }
        )

      assert ir.source_type == "github_actions"
      assert ir.source_file == ".github/workflows/ci.yml"
      assert ir.name == "CI"
      assert length(ir.triggers) == 1
      assert hd(ir.triggers).type == "push"
      assert ir.stages == ["build", "test"]
      assert map_size(ir.jobs) == 2
    end

    test "creates a GitLab CI IR from valid attrs" do
      ir =
        ExternalPipelineIR.new(
          source_type: "gitlab_ci",
          source_file: ".gitlab-ci.yml",
          name: "my-project",
          triggers: [],
          env_vars: %{},
          stages: ["build", "test", "deploy"],
          jobs: %{
            "build-job" => %{
              stage: "build",
              needs: [],
              steps: [%{type: "script", command: "make"}]
            },
            "test-job" => %{
              stage: "test",
              needs: ["build-job"],
              steps: [%{type: "script", command: "make test"}]
            }
          },
          includes: ["ci/build.gitlab-ci.yml"]
        )

      assert ir.source_type == "gitlab_ci"
      assert ir.stages == ["build", "test", "deploy"]
      assert ir.includes == ["ci/build.gitlab-ci.yml"]
      assert map_size(ir.jobs) == 2
    end

    test "defaults include empty list for includes" do
      ir =
        ExternalPipelineIR.new(
          source_type: "github_actions",
          source_file: "ci.yml",
          name: "CI",
          stages: ["build"],
          jobs: %{}
        )

      assert ir.includes == []
      assert ir.triggers == []
      assert ir.env_vars == %{}
    end

    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        ExternalPipelineIR.new(stages: ["build"])
      end
    end
  end

  describe "job_names/1" do
    test "returns sorted job names" do
      ir =
        ExternalPipelineIR.new(
          source_type: "github_actions",
          source_file: "ci.yml",
          name: "CI",
          stages: ["a", "b"],
          jobs: %{"b-job" => %{stage: "b"}, "a-job" => %{stage: "a"}}
        )

      assert ExternalPipelineIR.job_names(ir) == ["a-job", "b-job"]
    end
  end

  describe "trigger_types/1" do
    test "returns unique trigger types" do
      ir =
        ExternalPipelineIR.new(
          source_type: "github_actions",
          source_file: "ci.yml",
          name: "CI",
          stages: ["build"],
          jobs: %{},
          triggers: [
            %{type: "push", branches: ["main"]},
            %{type: "push", branches: ["dev"]},
            %{type: "schedule", cron: "0 0 * * *"}
          ]
        )

      assert ExternalPipelineIR.trigger_types(ir) == ["push", "schedule"]
    end
  end
end
