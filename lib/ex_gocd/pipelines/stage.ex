defmodule ExGoCD.Pipelines.Stage do
  @moduledoc """
  A stage consists of multiple jobs that can run independently in parallel.
  
  Stages run sequentially within a pipeline. If any job fails, the stage fails,
  but other jobs in the stage continue to completion.
  
  Based on GoCD concepts: https://docs.gocd.org/current/introduction/concepts_in_go.html#stage
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Pipeline, Job}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          fetch_materials: boolean(),
          clean_working_directory: boolean(),
          never_cleanup_artifacts: boolean(),
          approval_type: String.t(),
          environment_variables: map(),
          pipeline_id: integer() | nil,
          pipeline: Pipeline.t() | Ecto.Association.NotLoaded.t(),
          jobs: [Job.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "stages" do
    field :name, :string
    field :fetch_materials, :boolean, default: true
    field :clean_working_directory, :boolean, default: false
    field :never_cleanup_artifacts, :boolean, default: false
    field :approval_type, :string, default: "success"
    field :environment_variables, :map, default: %{}

    belongs_to :pipeline, Pipeline
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
      :pipeline_id
    ])
    |> validate_required([:name, :pipeline_id])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:approval_type, ["success", "manual"])
    |> foreign_key_constraint(:pipeline_id)
    |> unique_constraint([:name, :pipeline_id], name: :stages_pipeline_id_name_index)
  end
end
