defmodule ExGoCD.Pipelines.Stage do
  @moduledoc """
  A stage configuration defines a collection of jobs that can run in parallel.

  This represents StageConfig in GoCD - the definition/template, not a running instance.
  Stages run sequentially within a pipeline. If any job fails, the stage fails,
  but other jobs in the stage continue to completion.

  Based on GoCD source: config/config-api/.../StageConfig.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Job, Pipeline, Template}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          fetch_materials: boolean() | nil,
          clean_working_directory: boolean() | nil,
          never_cleanup_artifacts: boolean() | nil,
          approval_type: String.t() | nil,
          environment_variables: map() | nil,
          secure_variables: map() | nil,
          approval_authorization: map() | nil,
          pipeline_id: integer() | nil,
          template_id: integer() | nil,
          pipeline: Pipeline.t() | nil | Ecto.Association.NotLoaded.t(),
          template: Template.t() | nil | Ecto.Association.NotLoaded.t(),
          jobs: [Job.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "stages" do
    field :name, :string
    field :fetch_materials, :boolean, default: true
    field :clean_working_directory, :boolean, default: false
    field :never_cleanup_artifacts, :boolean, default: false
    field :approval_type, :string, default: "success"
    field :environment_variables, :map, default: %{}
    field :secure_variables, :map, default: %{}
    field :approval_authorization, :map, default: %{}

    belongs_to :pipeline, Pipeline
    belongs_to :template, Template
    has_many :jobs, Job, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a stage.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [
      :name,
      :fetch_materials,
      :clean_working_directory,
      :never_cleanup_artifacts,
      :approval_type,
      :environment_variables,
      :approval_authorization,
      :pipeline_id,
      :template_id
    ])
    |> validate_required([:name])
    |> validate_one_of_associations()
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:approval_type, ["success", "manual"])
    |> foreign_key_constraint(:pipeline_id)
    |> foreign_key_constraint(:template_id)
    |> unique_constraint([:name, :pipeline_id], name: :stages_pipeline_id_name_index)
  end

  defp validate_one_of_associations(changeset) do
    pipeline_id = get_field(changeset, :pipeline_id)
    template_id = get_field(changeset, :template_id)

    cond do
      is_nil(pipeline_id) and is_nil(template_id) ->
        add_error(changeset, :pipeline_id, "either pipeline_id or template_id must be present")

      not is_nil(pipeline_id) and not is_nil(template_id) ->
        add_error(changeset, :pipeline_id, "cannot define both pipeline_id and template_id")

      true ->
        changeset
    end
  end
end
