defmodule ExGoCD.AgentHealth do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "agent_healths" do
    field :agent_uuid, :string
    field :cpu_percent, :float
    field :memory_mb, :integer
    field :disk_free_mb, :integer
    field :disk_total_mb, :integer
    field :os, :string
    field :uptime_seconds, :integer
    field :reported_at, :utc_datetime

    timestamps(updated_at: false)
  end

  @required ~w(agent_uuid)a
  @optional ~w(cpu_percent memory_mb disk_free_mb disk_total_mb os uptime_seconds reported_at)a

  def changeset(health, attrs) do
    health
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> put_change(:reported_at, attrs[:reported_at] || DateTime.utc_now())
  end
end
