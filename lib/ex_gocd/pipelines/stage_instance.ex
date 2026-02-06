defmodule ExGoCD.Pipelines.StageInstance do
  @moduledoc """
  A stage instance represents a single execution of a stage within a pipeline instance.

  Stage instances track the status and timing of stage runs. Multiple stage instances
  can exist for the same stage (e.g., when manually re-running a stage).

  Based on GoCD source: domain/Stage.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{PipelineInstance, JobInstance}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          counter: integer(),
          order_id: integer(),
          state: String.t(),
          result: String.t(),
          approval_type: String.t(),
          approved_by: String.t() | nil,
          cancelled_by: String.t() | nil,
          created_time: DateTime.t(),
          last_transitioned_time: DateTime.t() | nil,
          scheduled_at: NaiveDateTime.t() | nil,
          completed_at: NaiveDateTime.t() | nil,
          fetch_materials: boolean(),
          clean_working_dir: boolean(),
          identifier: String.t() | nil,
          completed_by_transition_id: integer() | nil,
          latest_run: boolean(),
          rerun_of_counter: integer() | nil,
          artifacts_deleted: boolean(),
          config_version: String.t() | nil,
          pipeline_instance_id: integer() | nil,
          pipeline_instance: PipelineInstance.t() | Ecto.Association.NotLoaded.t(),
          job_instances: [JobInstance.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "stage_instances" do
    field :name, :string
    field :counter, :integer
    field :order_id, :integer
    field :state, :string
    field :result, :string, default: "Unknown"
    field :approval_type, :string
    field :approved_by, :string
    field :cancelled_by, :string
    field :created_time, :utc_datetime
    field :last_transitioned_time, :utc_datetime
    field :scheduled_at, :naive_datetime
    field :completed_at, :naive_datetime
    field :fetch_materials, :boolean, default: true
    field :clean_working_dir, :boolean, default: false
    field :identifier, :string
    field :completed_by_transition_id, :integer
    field :latest_run, :boolean, default: true
    field :rerun_of_counter, :integer
    field :artifacts_deleted, :boolean, default: false
    field :config_version, :string

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
      :order_id,
      :state,
      :result,
      :approval_type,
      :approved_by,
      :cancelled_by,
      :created_time,
      :last_transitioned_time,
      :scheduled_at,
      :completed_at,
      :fetch_materials,
      :clean_working_dir,
      :identifier,
      :completed_by_transition_id,
      :latest_run,
      :rerun_of_counter,
      :artifacts_deleted,
      :config_version,
      :pipeline_instance_id
    ])
    |> validate_required([:name, :counter, :order_id, :state, :approval_type, :created_time, :pipeline_instance_id])
    |> validate_number(:counter, greater_than: 0)
    |> validate_inclusion(:approval_type, ["success", "manual"])
    |> validate_inclusion(:result, ["Passed", "Failed", "Cancelled", "Unknown"])
    |> validate_inclusion(:state, ["Building", "Completed", "Cancelled"])
    |> foreign_key_constraint(:pipeline_instance_id)
    |> unique_constraint([:pipeline_instance_id, :name, :counter],
      name: :stage_instances_pipeline_instance_id_name_counter_index
    )
  end
end
