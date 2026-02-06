defmodule ExGoCD.Pipelines.Job do
  @moduledoc """
  A job configuration defines multiple tasks that run in order on a single agent.

  This represents JobConfig in GoCD - the definition/template, not a running instance.
  If a task fails, the job fails and remaining tasks won't run (unless configured otherwise).
  Jobs within a stage are independent and can run in parallel.

  Based on GoCD source: config/config-api/.../JobConfig.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Stage, Task}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          run_instance_count: String.t() | nil,
          timeout: String.t() | nil,
          resources: [String.t()],
          environment_variables: map(),
          run_on_all_agents: boolean(),
          elastic_profile_id: String.t() | nil,
          tabs: map(),
          artifact_configs: map(),
          stage_id: integer() | nil,
          stage: Stage.t() | Ecto.Association.NotLoaded.t(),
          tasks: [Task.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "jobs" do
    field :name, :string
    field :run_instance_count, :string
    field :timeout, :string  # "never" or numeric value
    field :resources, {:array, :string}, default: []
    field :environment_variables, :map, default: %{}
    field :run_on_all_agents, :boolean, default: false
    field :elastic_profile_id, :string
    field :tabs, :map, default: %{}
    field :artifact_configs, :map, default: %{}

    belongs_to :stage, Stage
    has_many :tasks, Task, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a job.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :name,
      :run_instance_count,
      :timeout,
      :resources,
      :environment_variables,
      :run_on_all_agents,
      :elastic_profile_id,
      :tabs,
      :artifact_configs,
      :stage_id
    ])
    |> validate_required([:name, :stage_id])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint([:stage_id, :name], name: :jobs_stage_id_name_index)
  end
end
