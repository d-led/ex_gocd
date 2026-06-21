defmodule ExGoCD.Analytics.AgentTransition do
  @moduledoc """
  Tracks agent state changes for utilization analytics.
  Mirrors GoCD analytics plugin's agent_transitions table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_state_transitions" do
    field :agent_uuid, :string
    field :from_state, :string
    field :to_state, :string
    field :transitioned_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(transition, attrs) do
    transition
    |> cast(attrs, [:agent_uuid, :from_state, :to_state, :transitioned_at])
    |> validate_required([:agent_uuid, :to_state, :transitioned_at])
  end
end
