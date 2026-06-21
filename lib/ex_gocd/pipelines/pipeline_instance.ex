defmodule ExGoCD.Pipelines.PipelineInstance do
  @moduledoc """
  A pipeline instance represents a single execution of a pipeline.

  Each time a pipeline is triggered, a new instance is created with an
  incrementing counter. Instances track what triggered it (BuildCause) and timing.

  Based on GoCD source: domain/Pipeline.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Pipeline, PipelineMaterialRevision, StageInstance}

  @type t :: %__MODULE__{
          id: integer() | nil,
          counter: integer() | nil,
          label: String.t() | nil,
          natural_order: float() | nil,
          build_cause: map() | nil,
          pipeline_id: integer() | nil,
          pipeline: Pipeline.t() | nil | Ecto.Association.NotLoaded.t(),
          stage_instances: [StageInstance.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pipeline_instances" do
    field :counter, :integer
    field :label, :string
    field :natural_order, :float
    field :build_cause, :map

    belongs_to :pipeline, Pipeline
    has_many :stage_instances, StageInstance, on_delete: :delete_all
    has_many :pipeline_material_revisions, PipelineMaterialRevision, on_delete: :delete_all

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
      :natural_order,
      :build_cause,
      :pipeline_id
    ])
    |> validate_required([:counter, :label, :natural_order, :build_cause, :pipeline_id])
    |> validate_number(:counter, greater_than: 0)
    |> foreign_key_constraint(:pipeline_id)
    |> unique_constraint([:pipeline_id, :counter],
      name: :pipeline_instances_pipeline_id_counter_index
    )
  end
end
