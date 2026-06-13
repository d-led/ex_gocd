defmodule ExGoCD.Pipelines.PipelineMaterialRevision do
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.Material
  alias ExGoCD.Pipelines.Modification
  alias ExGoCD.Pipelines.PipelineInstance

  @moduledoc """
  Represents a resolved material revision (PMR) for a given pipeline instance run.
  Enforces fan-in consistency check for SCM and parent pipeline dependencies.
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          pipeline_instance_id: integer() | nil,
          material_id: integer() | nil,
          modification_id: integer() | nil,
          parent_pipeline_instance_id: integer() | nil,
          revision: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pipeline_material_revisions" do
    field :revision, :string

    belongs_to :pipeline_instance, PipelineInstance
    belongs_to :material, Material
    belongs_to :modification, Modification
    belongs_to :parent_pipeline_instance, PipelineInstance

    timestamps(type: :utc_datetime)
  end

  def changeset(pmr, attrs) do
    pmr
    |> cast(attrs, [
      :pipeline_instance_id,
      :material_id,
      :modification_id,
      :parent_pipeline_instance_id,
      :revision
    ])
    |> validate_required([:pipeline_instance_id, :material_id, :revision])
    |> unique_constraint(
      [:pipeline_instance_id, :material_id],
      name: :pipeline_material_revisions_pipeline_instance_id_material_id_in
    )
  end
end
