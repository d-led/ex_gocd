defmodule ExGoCD.Pipelines.StageInstance do
  @moduledoc """
  A stage instance represents a single execution of a stage within a pipeline instance.
  
  Stage instances track the status and timing of stage runs. Multiple stage instances
  can exist for the same stage (e.g., when manually re-running a stage).
  
  Based on GoCD concepts: https://docs.gocd.org/current/introduction/concepts_in_go.html#stage
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Stage, PipelineInstance, JobInstance}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          counter: integer(),
          approval_type: String.t(),
          approved_by: String.t() | nil,
          cancelled_by: String.t() | nil,
          result: String.t(),
          state: String.t(),
          scheduled_at: NaiveDateTime.t() | nil,
          completed_at: NaiveDateTime.t() | nil,
          stage_id: integer() | nil,
          pipeline_instance_id: integer() | nil,
          stage: Stage.t() | Ecto.Association.NotLoaded.t(),
          pipeline_instance: PipelineInstance.t() | Ecto.Association.NotLoaded.t(),
          job_instances: [JobInstance.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "stage_instances" do
    field :name, :string
    field :counter, :integer
    field :approval_type, :string
    field :approved_by, :string
    field :cancelled_by, :string
    field :result, :string, default: "Unknown"
    field :state, :string, default: "Building"
    field :scheduled_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :stage, Stage
    belongs_to :pipeline_instance, PipelineInstance
    has_many :job_instances, JobInstance, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a stage instance.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :name,
      :counter,
      :approval_type,
      :approved_by,
      :cancelled_by,
      :result,
      :state,
      :scheduled_at,
      :completed_at,
      :stage_id,
      :pipeline_instance_id
    ])
    |> validate_required([:name, :counter, :approval_type, :result, :state, :stage_id, :pipeline_instance_id])
    |> validate_number(:counter, greater_than: 0)
    |> validate_inclusion(:approval_type, ["success", "manual"])
    |> validate_inclusion(:result, ["Passed", "Failed", "Cancelled", "Unknown"])
    |> validate_inclusion(:state, ["Building", "Completed", "Cancelled"])
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:pipeline_instance_id)
    |> unique_constraint([:pipeline_instance_id, :name, :counter],
      name: :stage_instances_pipeline_instance_id_name_counter_index
    )
  end
end
