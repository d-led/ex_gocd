defmodule ExGoCD.Pipelines.Job do
  @moduledoc """
  A job consists of multiple tasks that run in order on a single agent.

  If a task fails, the job fails and remaining tasks won't run (unless configured otherwise).
  Jobs within a stage are independent and can run in parallel.

  Based on GoCD concepts: https://docs.gocd.org/current/introduction/concepts_in_go.html#job
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Stage, Task}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          run_instance_count: String.t() | nil,
          timeout: integer() | nil,
          resources: [String.t()],
          environment_variables: map(),
          stage_id: integer() | nil,
          stage: Stage.t() | Ecto.Association.NotLoaded.t(),
          tasks: [Task.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "jobs" do
    field :name, :string
    field :run_instance_count, :string
    field :timeout, :integer, default: 0
    field :resources, {:array, :string}, default: []
    field :environment_variables, :map, default: %{}

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
    |> cast(attrs, [:name, :run_instance_count, :timeout, :resources, :environment_variables, :stage_id])
    |> validate_required([:name, :stage_id])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:run_instance_count, greater_than_or_equal_to: 1)
    |> validate_number(:timeout, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:stage_id)
    |> unique_constraint([:name, :stage_id], name: :jobs_stage_id_name_index)
  end
end
