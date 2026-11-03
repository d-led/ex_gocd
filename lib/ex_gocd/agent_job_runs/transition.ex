defmodule ExGoCD.AgentJobRuns.Transition do
  @moduledoc """
  One state a job run entered, and when. GoCD reports these as
  `job_state_transitions` in a job's history; keeping them is what lets the
  history say more than "it ended up Passed".
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_job_run_transitions" do
    field :state, :string
    field :changed_at, :utc_datetime

    belongs_to :agent_job_run, ExGoCD.AgentJobRuns.AgentJobRun
  end

  def changeset(transition, attrs) do
    transition
    |> cast(attrs, [:state, :changed_at, :agent_job_run_id])
    |> validate_required([:state, :changed_at, :agent_job_run_id])
  end
end
