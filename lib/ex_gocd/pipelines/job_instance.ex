defmodule ExGoCD.Pipelines.JobInstance do
  @moduledoc """
  Represents a job instance - a single execution of a job within a stage.

  A job instance is the actual runtime execution of a job configuration.
  It tracks state (Scheduled, Assigned, Building, Completed), result (Passed/Failed),
  which agent ran it, and timing information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.Stage

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          state: String.t(),
          result: String.t(),
          agent_uuid: String.t() | nil,
          scheduled_date: NaiveDateTime.t() | nil,
          state_transitions: map(),
          ignored: boolean(),
          run_on_all_agents: boolean(),
          run_multiple_instance: boolean(),
          original_job_id: integer() | nil,
          rerun: boolean(),
          stage_id: integer() | nil,
          stage: Stage.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "job_instances" do
    field :name, :string
    field :state, :string, default: "Scheduled"
    field :result, :string, default: "Unknown"
    field :agent_uuid, :string
    field :scheduled_date, :utc_datetime
    field :state_transitions, :map, default: %{}
    field :ignored, :boolean, default: false
    field :run_on_all_agents, :boolean, default: false
    field :run_multiple_instance, :boolean, default: false
    field :original_job_id, :integer
    field :rerun, :boolean, default: false

    belongs_to :stage, Stage

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a job instance.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(job_instance, attrs) do
    job_instance
    |> cast(attrs, [
      :name,
      :state,
      :result,
      :agent_uuid,
      :scheduled_date,
      :state_transitions,
      :ignored,
      :run_on_all_agents,
      :run_multiple_instance,
      :original_job_id,
      :rerun,
      :stage_id
    ])
    |> validate_required([:name, :stage_id])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:state, ["Scheduled", "Assigned", "Preparing", "Building", "Completing", "Completed", "Rescheduled", "Unknown"])
    |> validate_inclusion(:result, ["Passed", "Failed", "Cancelled", "Unknown"])
    |> foreign_key_constraint(:stage_id)
    |> unique_constraint([:stage_id, :name], name: :job_instances_stage_id_name_index)
  end
end
