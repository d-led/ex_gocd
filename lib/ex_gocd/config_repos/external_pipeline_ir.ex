defmodule ExGoCD.ConfigRepos.ExternalPipelineIR do
  @moduledoc """
  Intermediate Representation for external CI pipeline configs.

  Both GitHub Actions and GitLab CI parsers produce this unified struct.
  The translation engine consumes it to produce GoCD pipeline configurations.

  ## Fields

  - `source_type` — `"github_actions"` or `"gitlab_ci"`
  - `source_file` — relative path within the config repo
  - `name` — pipeline/workflow name
  - `triggers` — list of trigger maps with `:type` ("push", "pull_request", "schedule", "workflow_dispatch", "web")
  - `env_vars` — top-level environment variables
  - `stages` — ordered list of stage names
  - `jobs` — map of job_name → job details (stage, needs, steps, runs_on, image, services, artifacts)
  - `includes` — list of resolved include file paths (GitLab CI)
  """
  defstruct [
    :source_type,
    :source_file,
    :name,
    triggers: [],
    env_vars: %{},
    stages: [],
    jobs: %{},
    includes: []
  ]

  @required [:source_type, :source_file, :name, :stages, :jobs]
  @valid_source_types ["github_actions", "gitlab_ci"]

  @doc """
  Creates a new ExternalPipelineIR struct with validation.
  """
  def new(attrs) when is_list(attrs) do
    struct = struct!(__MODULE__, attrs)

    for field <- @required do
      if is_nil(Map.get(struct, field)) do
        raise ArgumentError, "ExternalPipelineIR requires :#{field}"
      end
    end

    if struct.source_type not in @valid_source_types do
      raise ArgumentError,
            "ExternalPipelineIR source_type must be one of #{inspect(@valid_source_types)}, got: #{inspect(struct.source_type)}"
    end

    struct
  end

  @doc """
  Returns sorted list of job names from the IR.
  """
  def job_names(%__MODULE__{jobs: jobs}) do
    jobs |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns unique trigger types from the IR.
  """
  def trigger_types(%__MODULE__{triggers: triggers}) do
    triggers |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()
  end
end
