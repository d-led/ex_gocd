defmodule ExGoCD.Analytics.AgentSnapshot do
  @moduledoc """
  Periodic snapshot of agent utilization — mirrors GoCD's agent_utilization data.

  A GenServer captures the number of idle, building, and disabled agents
  every 5 minutes. Queried by the Analytics dashboard for trend charts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_snapshots" do
    field :total, :integer
    field :idle, :integer
    field :building, :integer
    field :disabled, :integer, default: 0
    field :lost_contact, :integer, default: 0
    field :elastic, :integer, default: 0

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:total, :idle, :building, :disabled, :lost_contact, :elastic])
    |> validate_required([:total, :idle, :building])
  end
end
