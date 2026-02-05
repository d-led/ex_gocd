defmodule ExGoCDWeb.TestFixtures do
  @moduledoc """
  Test data builders for GoCD entities.

  Follows the "Mother" pattern from the original GoCD codebase,
  providing centralized test data creation for consistency across tests.
  """

  @doc """
  Creates a basic pipeline configuration.

  ## Examples

      iex> pipeline("my-pipeline")
      %{name: "my-pipeline", group: "default", stages: []}

      iex> pipeline("deployment", group: "production")
      %{name: "deployment", group: "production", stages: []}
  """
  def pipeline(name, opts \\ []) do
    %{
      name: name,
      group: Keyword.get(opts, :group, "default"),
      stages: Keyword.get(opts, :stages, []),
      materials: Keyword.get(opts, :materials, [])
    }
  end

  @doc """
  Creates a pipeline with multiple stages.

  ## Examples

      iex> pipeline_with_stages("build-pipeline", ["compile", "test", "package"])
      %{
        name: "build-pipeline",
        group: "default",
        stages: [
          %{name: "compile", jobs: []},
          %{name: "test", jobs: []},
          %{name: "package", jobs: []}
        ]
      }
  """
  def pipeline_with_stages(name, stage_names) when is_list(stage_names) do
    stages = Enum.map(stage_names, fn stage_name -> stage(stage_name) end)
    pipeline(name, stages: stages)
  end

  @doc """
  Creates a stage configuration.

  ## Examples

      iex> stage("build")
      %{name: "build", jobs: [], approval_type: "auto"}

      iex> stage("deploy", approval_type: "manual")
      %{name: "deploy", jobs: [], approval_type: "manual"}
  """
  def stage(name, opts \\ []) do
    %{
      name: name,
      jobs: Keyword.get(opts, :jobs, []),
      approval_type: Keyword.get(opts, :approval_type, "auto")
    }
  end

  @doc """
  Creates a job configuration.

  ## Examples

      iex> job("unit-tests")
      %{name: "unit-tests", tasks: []}

      iex> job("deploy", tasks: [%{type: "exec", command: "deploy.sh"}])
      %{name: "deploy", tasks: [%{type: "exec", command: "deploy.sh"}]}
  """
  def job(name, opts \\ []) do
    %{
      name: name,
      tasks: Keyword.get(opts, :tasks, [])
    }
  end

  @doc """
  Creates a Git material configuration.

  ## Examples

      iex> git_material("https://github.com/gocd/gocd.git")
      %{
        type: "git",
        url: "https://github.com/gocd/gocd.git",
        branch: "master"
      }

      iex> git_material("https://github.com/gocd/gocd.git", branch: "develop")
      %{
        type: "git",
        url: "https://github.com/gocd/gocd.git",
        branch: "develop"
      }
  """
  def git_material(url, opts \\ []) do
    %{
      type: "git",
      url: url,
      branch: Keyword.get(opts, :branch, "master")
    }
  end

  @doc """
  Creates a pipeline instance (a specific run of a pipeline).

  ## Examples

      iex> pipeline_instance("my-pipeline", counter: 42)
      %{
        pipeline_name: "my-pipeline",
        counter: 42,
        status: "Building",
        stages: []
      }

      iex> pipeline_instance("my-pipeline", counter: 1, status: "Passed")
      %{
        pipeline_name: "my-pipeline",
        counter: 1,
        status: "Passed",
        stages: []
      }
  """
  def pipeline_instance(pipeline_name, opts \\ []) do
    %{
      pipeline_name: pipeline_name,
      counter: Keyword.get(opts, :counter, 1),
      status: Keyword.get(opts, :status, "Building"),
      stages: Keyword.get(opts, :stages, [])
    }
  end

  @doc """
  Creates a completed pipeline instance with all stages passed.

  ## Examples

      iex> completed_pipeline("my-pipeline", ["build", "test"])
      %{
        pipeline_name: "my-pipeline",
        counter: 1,
        status: "Passed",
        stages: [
          %{name: "build", status: "Passed"},
          %{name: "test", status: "Passed"}
        ]
      }
  """
  def completed_pipeline(pipeline_name, stage_names) do
    stages =
      Enum.map(stage_names, fn name ->
        %{name: name, status: "Passed"}
      end)

    pipeline_instance(pipeline_name, status: "Passed", stages: stages)
  end

  @doc """
  Creates a failed pipeline instance.

  ## Examples

      iex> failed_pipeline("my-pipeline", failing_stage: "test")
      %{
        pipeline_name: "my-pipeline",
        counter: 1,
        status: "Failed",
        stages: [
          %{name: "build", status: "Passed"},
          %{name: "test", status: "Failed"}
        ]
      }
  """
  def failed_pipeline(pipeline_name, opts \\ []) do
    failing_stage = Keyword.get(opts, :failing_stage, "test")

    stages = [
      %{name: "build", status: "Passed"},
      %{name: failing_stage, status: "Failed"}
    ]

    pipeline_instance(pipeline_name, status: "Failed", stages: stages)
  end
end
