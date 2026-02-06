defmodule ExGoCD.Pipelines.PipelineInstance do
  @moduledoc """
  A pipeline instance represents a single execution of a pipeline.

  Each time a pipeline is triggered, a new instance is created with an
  incrementing counter. Instances track status, who triggered it, and timing.

  Based on GoCD concepts: https://docs.gocd.org/current/introduction/concepts_in_go.html#pipeline
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Pipeline, StageInstance}

  @type t :: %__MODULE__{
          id: integer() | nil,
          counter: integer(),
          label: String.t(),
          status: String.t(),
          triggered_by: String.t(),
          trigger_message: String.t() | nil,
          natural_order: float() | nil,
          scheduled_at: NaiveDateTime.t() | nil,
          completed_at: NaiveDateTime.t() | nil,
          pipeline_id: integer() | nil,
          pipeline: Pipeline.t() | Ecto.Association.NotLoaded.t(),
          stage_instances: [StageInstance.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "pipeline_instances" do
    field :counter, :integer
    field :label, :string
    field :status, :string, default: "Building"
    field :triggered_by, :string
    field :trigger_message, :string
    field :natural_order, :float
    field :scheduled_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :pipeline, Pipeline
    has_many :stage_instances, StageInstance, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a pipeline instance.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :counter,
      :label,
      :status,
      :triggered_by,
      :trigger_message,
      :natural_order,
      :scheduled_at,
      :completed_at,
      :pipeline_id
    ])
    |> validate_required([:counter, :label, :status, :triggered_by, :pipeline_id])
    |> validate_number(:counter, greater_than: 0)
    |> validate_inclusion(:status, ["Building", "Passed", "Failed", "Cancelled", "Paused"])
    |> foreign_key_constraint(:pipeline_id)
    |> unique_constraint([:pipeline_id, :counter], name: :pipeline_instances_pipeline_id_counter_index)
  end
end
