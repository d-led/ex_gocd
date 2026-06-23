defmodule ExGoCD.ConfigReposTest do
  @moduledoc """
  Tests for config repos (pipeline-as-code) — parsing JSON definitions
  and upserting pipeline configurations.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.ConfigRepos
  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  @valid_pipeline_json """
  {
    "pipelines": [
      {
        "name": "config-repo-pipe",
        "group": "test",
        "label_template": "cr-${COUNT}",
        "parameters": {"VERSION": "1.0"},
        "materials": [
          {
            "type": "git",
            "url": "https://github.com/example/repo.git",
            "branch": "main"
          }
        ],
        "stages": [
          {
            "name": "build",
            "approval_type": "success",
            "jobs": [
              {
                "name": "compile",
                "resources": [],
                "tasks": [
                  {
                    "type": "exec",
                    "command": "make",
                    "arguments": ["build"]
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
  """

  describe "config repo CRUD" do
    test "creates a config repo" do
      assert {:ok, cr} =
               ConfigRepos.create_config_repo(%{url: "https://github.com/example/pipelines.git"})

      assert cr.url == "https://github.com/example/pipelines.git"
      assert cr.branch == "main"
      assert cr.material_type == "git"
    end

    test "lists config repos" do
      {:ok, _} = ConfigRepos.create_config_repo(%{url: "https://github.com/example/repo1.git"})
      {:ok, _} = ConfigRepos.create_config_repo(%{url: "https://github.com/example/repo2.git"})
      repos = ConfigRepos.list_config_repos()
      assert length(repos) == 2
    end

    test "deletes a config repo" do
      {:ok, cr} =
        ConfigRepos.create_config_repo(%{url: "https://github.com/example/to-delete.git"})

      assert {:ok, _} = ConfigRepos.delete_config_repo(cr)
      assert ConfigRepos.get_config_repo(cr.id) == nil
    end

    test "validates URL format" do
      assert {:error, changeset} = ConfigRepos.create_config_repo(%{url: "not-a-url"})
      assert "must be a valid git URL" in errors_on(changeset).url
    end

    test "enforces unique URL" do
      {:ok, _} = ConfigRepos.create_config_repo(%{url: "https://github.com/example/unique.git"})

      assert {:error, _} =
               ConfigRepos.create_config_repo(%{url: "https://github.com/example/unique.git"})
    end
  end

  describe "refresh_config_repo_with_content/2" do
    test "parses JSON and creates pipeline with stages and jobs" do
      {:ok, cr} =
        ConfigRepos.create_config_repo(%{url: "https://github.com/example/parser-test.git"})

      assert {:ok, 1} = ConfigRepos.refresh_config_repo_with_content(cr, @valid_pipeline_json)

      pipeline = Pipelines.get_pipeline_by_name("config-repo-pipe")
      assert pipeline != nil
      assert pipeline.group == "test"
      assert pipeline.parameters == %{"VERSION" => "1.0"}

      pipeline = Repo.preload(pipeline, [:materials, stages: [jobs: :tasks]])
      assert length(pipeline.stages) == 1
      assert hd(pipeline.stages).name == "build"
      assert length(hd(pipeline.stages).jobs) == 1
      assert hd(hd(pipeline.stages).jobs).name == "compile"
      assert length(pipeline.materials) == 1
      assert hd(pipeline.materials).url == "https://github.com/example/repo.git"
    end

    test "updates existing pipeline on re-parse" do
      {:ok, cr} =
        ConfigRepos.create_config_repo(%{url: "https://github.com/example/reparse-test.git"})

      assert {:ok, 1} = ConfigRepos.refresh_config_repo_with_content(cr, @valid_pipeline_json)

      pipeline = Pipelines.get_pipeline_by_name("config-repo-pipe")
      assert pipeline.group == "test"

      # Re-parse with updated group
      updated_json =
        String.replace(@valid_pipeline_json, ~s("group": "test"), ~s("group": "production"))

      assert {:ok, 1} = ConfigRepos.refresh_config_repo_with_content(cr, updated_json)

      pipeline = Pipelines.get_pipeline_by_name("config-repo-pipe")
      assert pipeline.group == "production"
    end

    test "updates last_parsed_at on success" do
      {:ok, cr} =
        ConfigRepos.create_config_repo(%{url: "https://github.com/example/timestamp-test.git"})

      assert {:ok, 1} = ConfigRepos.refresh_config_repo_with_content(cr, @valid_pipeline_json)

      cr = ConfigRepos.get_config_repo(cr.id)
      assert cr.last_parsed_at != nil
      assert cr.error_message == nil
    end

    test "sets error_message on parse failure" do
      {:ok, cr} =
        ConfigRepos.create_config_repo(%{url: "https://github.com/example/error-test.git"})

      assert {:error, _} = ConfigRepos.refresh_config_repo_with_content(cr, "not valid json {{{")

      cr = ConfigRepos.get_config_repo(cr.id)
      assert cr.error_message != nil
    end

    test "pipelines with no stages do not fail" do
      {:ok, cr} =
        ConfigRepos.create_config_repo(%{url: "https://github.com/example/no-stages.git"})

      json = ~s({"pipelines": [{"name": "no-stage-pipe", "group": "test"}]})

      assert {:ok, 1} = ConfigRepos.refresh_config_repo_with_content(cr, json)
      pipeline = Pipelines.get_pipeline_by_name("no-stage-pipe")
      assert pipeline != nil
    end
  end
end
