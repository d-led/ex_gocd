defmodule ExGoCD.Pipelines.Pipeline do
  @moduledoc """
  A pipeline consists of multiple stages that run sequentially.
  
  If a stage fails, the pipeline fails and following stages won't run.
  Pipelines are triggered by materials and each run creates a pipeline instance.
  
  Based on GoCD concepts: https://docs.gocd.org/current/introduction/concepts_in_go.html#pipeline
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Stage, Material, PipelineInstance}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          group: String.t(),
          label_template: String.t(),
          lock_behavior: String.t(),
          environment_variables: map(),
          timer: String.t() | nil,
          stages: [Stage.t()],
          materials: [Material.t()],
          instances: [PipelineInstance.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "pipelines" do
    field :name, :string
    field :group, :string
    field :label_template, :string, default: "${COUNT}"
    field :lock_behavior, :string, default: "none"
    field :environment_variables, :map, default: %{}
    field :timer, :string

    has_many :stages, Stage, on_delete: :delete_all
    many_to_many :materials, Material, join_through: "pipelines_materials", on_delete: :delete_all
    has_many :instances, PipelineInstance, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a pipeline.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pipeline, attrs) do
    pipeline
    |> cast(attrs, [:name, :group, :label_template, :lock_behavior, :environment_variables, :timer])
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:group, min: 1, max: 255)
    |> validate_inclusion(:lock_behavior, ["none", "lockOnFailure", "unlockWhenFinished"])
    |> unique_constraint(:name)
  end
end
