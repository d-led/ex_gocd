defmodule ExGoCD.Pipelines.Pipeline do
  @moduledoc """
  A pipeline configuration defines how to build and deploy software.

  This represents PipelineConfig in GoCD - the definition/template, not a running instance.
  Pipelines are triggered by materials and each run creates a pipeline instance.

  Based on GoCD source: config/config-api/.../PipelineConfig.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.ConfigRepos.ConfigRepo
  alias ExGoCD.Pipelines.{Material, PipelineInstance, Stage, Template}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          group: String.t() | nil,
          label_template: String.t() | nil,
          lock_behavior: String.t() | nil,
          secure_variables: map() | nil,
          timer: String.t() | nil,
          timer_only_on_changes: boolean() | nil,
          params: map() | nil,
          parameters: map() | nil,
          tracking_tool: map() | nil,
          template_name: String.t() | nil,
          template_id: integer() | nil,
          template: Template.t() | nil | Ecto.Association.NotLoaded.t(),
          config_repo_id: integer() | nil,
          config_repo: ConfigRepo.t() | nil | Ecto.Association.NotLoaded.t(),
          source_file_path: String.t() | nil,
          display_order_weight: integer() | nil,
          paused: boolean() | nil,
          paused_by: String.t() | nil,
          pause_cause: String.t() | nil,
          paused_at: DateTime.t() | nil,
          locked: boolean() | nil,
          stages: [Stage.t()] | Ecto.Association.NotLoaded.t(),
          materials: [Material.t()] | Ecto.Association.NotLoaded.t(),
          instances: [PipelineInstance.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pipelines" do
    field :name, :string
    field :group, :string
    field :label_template, :string, default: "${COUNT}"
    field :lock_behavior, :string, default: "none"
    field :environment_variables, :map, default: %{}
    field :secure_variables, :map, default: %{}
    field :timer, :string
    field :timer_only_on_changes, :boolean, default: false
    field :params, :map, default: %{}
    field :parameters, :map, default: %{}
    field :tracking_tool, :map
    field :template_name, :string

    belongs_to :template, Template
    belongs_to :config_repo, ConfigRepo
    field :source_file_path, :string
    field :display_order_weight, :integer, default: -1
    field :paused, :boolean, default: false
    field :paused_by, :string
    field :pause_cause, :string
    field :paused_at, :utc_datetime
    field :locked, :boolean, default: false

    has_many :stages, Stage, on_delete: :delete_all
    many_to_many :materials, Material, join_through: "pipelines_materials", on_delete: :delete_all, on_replace: :delete
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
      :timer_only_on_changes,
      :params,
      :parameters,
      :tracking_tool,
      :template_name,
      :template_id,
      :config_repo_id,
      :source_file_path,
      :display_order_weight,
      :paused,
      :paused_by,
      :pause_cause,
      :paused_at,
      :locked
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
