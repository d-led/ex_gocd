defmodule ExGoCD.Pipelines.Modification do
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.Material

  @moduledoc """
  A Modification represents a specific revision/commit in an SCM material.
  Based on GoCD source: domain/materials/Modification.java
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          material_id: integer() | nil,
          revision: String.t() | nil,
          committer_name: String.t() | nil,
          committer_email: String.t() | nil,
          comment: String.t() | nil,
          modified_time: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "modifications" do
    field :revision, :string
    field :committer_name, :string
    field :committer_email, :string
    field :comment, :string
    field :modified_time, :utc_datetime

    belongs_to :material, Material

    timestamps(type: :utc_datetime)
  end

  def changeset(modification, attrs) do
    modification
    |> cast(attrs, [
      :material_id,
      :revision,
      :committer_name,
      :committer_email,
      :comment,
      :modified_time
    ])
    |> validate_required([:material_id, :revision, :modified_time])
    |> unique_constraint([:material_id, :revision],
      name: :modifications_material_id_revision_index
    )
  end
end
