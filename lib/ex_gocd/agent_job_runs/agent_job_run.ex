defmodule ExGoCD.AgentJobRuns.AgentJobRun do
  @moduledoc """
  Schema for a single job run executed on an agent.
  Created when a build is sent (e.g. Run test job); updated when agent reports completion.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_job_runs" do
    field :agent_uuid, :string
    field :build_id, :string
    field :pipeline_name, :string
    field :pipeline_counter, :integer, default: 1
    field :stage_name, :string
    field :stage_counter, :integer, default: 1
    field :job_name, :string
    field :result, :string
    field :state, :string, default: "Scheduled"
    field :console_log, :string, default: ""

    timestamps(type: :utc_datetime)
  end

  @required [:agent_uuid, :build_id, :pipeline_name, :stage_name, :job_name]
  @optional [:result, :state, :pipeline_counter, :stage_counter, :console_log]

  def changeset(run, attrs) do
    run
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:agent_uuid, :build_id])
  end
end
