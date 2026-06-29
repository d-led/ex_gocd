defmodule ExGoCD.ClusterEventLog do
  @moduledoc """
  Observable cluster event log — records node joins/leaves, plugin registrations,
  singleton migrations, and other cluster lifecycle events.

  Similar pattern to the agent scheduling decision log — keeps the last N events
  for display on the clustering admin page.
  """
  use GenServer

  @max_entries 100

  # -- Client API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Records a cluster event."
  def record(type, details \\ %{}) do
    GenServer.cast(__MODULE__, {:record, type, details})
  end

  @doc "Returns the last N events, newest first."
  def events(limit \\ 50) do
    GenServer.call(__MODULE__, {:events, limit})
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    {:ok, []}
  end

  @impl true
  def handle_call({:events, limit}, _from, state) do
    {:reply, Enum.take(state, limit), state}
  end

  @impl true
  def handle_cast({:record, type, details}, state) do
    entry = %{
      type: type,
      details: details,
      timestamp: DateTime.utc_now(),
      node: to_string(Node.self())
    }

    {:noreply, [entry | Enum.take(state, @max_entries - 1)]}
  end
end
