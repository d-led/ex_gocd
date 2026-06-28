defmodule ExGoCD.Analytics.SnapshotCollector do
  @moduledoc """
  Periodic GenServer that captures agent utilization snapshots.

  Every 5 minutes (configurable), queries agent state counts and inserts
  a row into `agent_snapshots` for trend analysis in the Analytics dashboard.

  Started by the application supervisor; no-op in test env.
  """

  use GenServer
  alias ExGoCD.{Repo, Analytics.AgentSnapshot}
  alias ExGoCD.Agents.Agent
  import Ecto.Query

  @default_interval_ms 5 * 60 * 1000

  # -- Public API --

  def start_link(opts \\ []) do
    if Application.get_env(:ex_gocd, :env) == :test do
      :ignore
    else
      interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
      ExGoCD.DistSingleton.start_link(__MODULE__, interval)
    end
  end

  def snapshot_now do
    ExGoCD.DistSingleton.call(__MODULE__, :snapshot)
  end

  # -- Callbacks --

  @impl true
  def init(interval_ms) do
    {:ok, _} = :timer.send_interval(interval_ms, :tick)
    # Also take one immediately on startup
    send(self(), :tick)
    {:ok, interval_ms}
  end

  @impl true
  def handle_info(:tick, state) do
    do_snapshot()
    ExGoCD.Agents.clean_test_agents()
    {:noreply, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    result = do_snapshot()
    {:reply, result, state}
  end

  # -- Internal --

  defp do_snapshot do
    counts = agent_state_counts()

    %AgentSnapshot{}
    |> AgentSnapshot.changeset(%{
      total: counts[:total],
      idle: counts[:idle],
      building: counts[:building],
      disabled: counts[:disabled],
      lost_contact: counts[:lost_contact],
      elastic: counts[:elastic]
    })
    |> Repo.insert()
  end

  defp agent_state_counts do
    # Query the agents table for state counts
    rows =
      from(a in Agent,
        where: a.deleted == false,
        group_by: a.state,
        select: {a.state, count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    idle = Map.get(rows, "Idle", 0)
    building = Map.get(rows, "Building", 0)
    disabled = Map.get(rows, "Disabled", 0)
    lost = Map.get(rows, "LostContact", 0)

    # Elastic = agents with a non-nil elastic_agent_id
    elastic =
      from(a in Agent,
        where: a.deleted == false and not is_nil(a.elastic_agent_id),
        select: count(a.id)
      )
      |> Repo.one() || 0

    %{
      total: idle + building + disabled + lost,
      idle: idle,
      building: building,
      disabled: disabled,
      lost_contact: lost,
      elastic: elastic
    }
  end
end
