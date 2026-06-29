defmodule RegionalAffinity.SchedulingDecisions do
  @moduledoc """
  GenServer that logs the 200 most recent agent scheduling decisions.
  Exposed via LiveView at /plugins in this app.
  """
  use GenServer

  @max_entries 200

  # -- Client API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns all recorded decisions, newest first."
  def decisions do
    GenServer.call(__MODULE__, :decisions)
  end

  @doc "Returns decisions involving a specific agent UUID."
  def decisions_for(agent_uuid) do
    GenServer.call(__MODULE__, {:decisions_for, agent_uuid})
  end

  @doc "Records a scheduling decision."
  def record(candidates, result) do
    GenServer.cast(__MODULE__, {:record, candidates, result})
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    {:ok, []}
  end

  @impl true
  def handle_call(:decisions, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:decisions_for, uuid}, _from, state) do
    filtered =
      Enum.filter(state, fn d -> d[:chosen] == uuid or uuid in (d[:candidates] || []) end)

    {:reply, filtered, state}
  end

  @impl true
  def handle_cast({:record, candidates, result}, state) do
    entry = %{
      timestamp: DateTime.utc_now(),
      candidates: Enum.map(candidates, & &1.uuid),
      chosen: result,
      node: to_string(Node.self())
    }

    new_state = [entry | Enum.take(state, @max_entries - 1)]

    # Broadcast to LiveView subscribers
    Phoenix.PubSub.broadcast(RegionalAffinity.PubSub, "plugin:decisions", {:new_decision, entry})

    {:noreply, new_state}
  end
end
