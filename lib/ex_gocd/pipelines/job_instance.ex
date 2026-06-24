defmodule ExGoCD.Pipelines.JobInstance do
  @moduledoc """
  A job instance represents a single execution of a job within a stage instance.

  Job instances track the status, timing, and agent assignment for job runs.
  They also track console output and test results.

  Based on GoCD source: domain/JobInstance.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Job, StageInstance}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          state: String.t() | nil,
          result: String.t() | nil,
          agent_uuid: String.t() | nil,
          scheduled_at: DateTime.t() | nil,
          assigned_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          run_on_all_agents: boolean() | nil,
          run_multiple_instance: boolean() | nil,
          ignored: boolean() | nil,
          identifier: String.t() | nil,
          original_job_id: integer() | nil,
          rerun: boolean() | nil,
          job_id: integer() | nil,
          stage_instance_id: integer() | nil,
          job: Job.t() | nil | Ecto.Association.NotLoaded.t(),
          stage_instance: StageInstance.t() | nil | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "job_instances" do
    field :name, :string
    field :state, :string, default: "Scheduled"
    field :result, :string, default: "Unknown"
    field :agent_uuid, :string
    field :scheduled_at, :utc_datetime_usec
    field :assigned_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :run_on_all_agents, :boolean, default: false
    field :run_multiple_instance, :boolean, default: false
    field :ignored, :boolean, default: false
    field :identifier, :string
    field :original_job_id, :integer
    field :rerun, :boolean, default: false

    belongs_to :job, Job
    belongs_to :stage_instance, StageInstance

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a job instance.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :name,
      :state,
      :result,
      :agent_uuid,
      :scheduled_at,
      :assigned_at,
      :completed_at,
      :run_on_all_agents,
      :run_multiple_instance,
      :ignored,
      :identifier,
      :original_job_id,
      :rerun,
      :job_id,
      :stage_instance_id
    ])
    |> validate_required([:name, :scheduled_at, :stage_instance_id])
    |> validate_inclusion(:state, [
      "Scheduled",
      "Assigned",
      "Preparing",
      "Building",
      "Completing",
      "Completed",
      "Rescheduled",
      "Cancelled",
      "Awaiting"
    ])
    |> validate_inclusion(:result, ["Passed", "Failed", "Cancelled", "Unknown"])
    |> foreign_key_constraint(:job_id)
    |> foreign_key_constraint(:stage_instance_id)
  end
end
