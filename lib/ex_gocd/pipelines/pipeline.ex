defmodule ExGoCD.Pipelines.Pipeline do
  @moduledoc """
  A pipeline configuration defines how to build and deploy software.

  This represents PipelineConfig in GoCD - the definition/template, not a running instance.
  Pipelines are triggered by materials and each run creates a pipeline instance.

  Based on GoCD source: config/config-api/.../PipelineConfig.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Stage, Material, PipelineInstance}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          group: String.t() | nil,
          label_template: String.t(),
          lock_behavior: String.t(),
          environment_variables: map(),
          timer: String.t() | nil,
          params: map(),
          tracking_tool: map() | nil,
          template_name: String.t() | nil,
          display_order_weight: integer(),
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
    field :params, :map, default: %{}
    field :tracking_tool, :map
    field :template_name, :string
    field :display_order_weight, :integer, default: -1

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
    |> cast(attrs, [
      :name,
      :group,
      :label_template,
      :lock_behavior,
      :environment_variables,
      :timer,
      :params,
      :tracking_tool,
      :template_name,
      :display_order_weight
    ])
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
