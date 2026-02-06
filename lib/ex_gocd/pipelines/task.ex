defmodule ExGoCD.Pipelines.Task do
  @moduledoc """
  A task is a single action that needs to be performed, typically a command.

  Tasks run sequentially within a job. Each task runs as an independent program,
  so environment variable changes don't carry over, but filesystem changes do.

  Based on GoCD source: config/config-api/.../ExecTask.java, AntTask.java, etc. (Task interface)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.Job

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t(),
          command: String.t() | nil,
          arguments: [String.t()],
          working_directory: String.t() | nil,
          run_if: String.t(),
          timeout: integer() | nil,
          on_cancel: map() | nil,
          job_id: integer() | nil,
          job: Job.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "tasks" do
    field :type, :string
    field :command, :string
    field :arguments, {:array, :string}, default: []
    field :working_directory, :string
    field :run_if, :string, default: "passed"
    field :timeout, :integer
    field :on_cancel, :map

    belongs_to :job, Job

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a task.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:type, :command, :arguments, :working_directory, :run_if, :timeout, :on_cancel, :job_id])
    |> validate_required([:type, :job_id])
    |> validate_inclusion(:type, ["exec", "ant", "nant", "rake", "fetch", "plugin"])
    |> validate_inclusion(:run_if, ["passed", "failed", "any"])
    |> validate_command_for_type()
    |> foreign_key_constraint(:job_id)
  end

  defp validate_command_for_type(changeset) do
    type = get_field(changeset, :type)

    if type in ["exec", "ant", "nant", "rake"] do
      validate_required(changeset, [:command])
    else
      changeset
    end
  end
end
