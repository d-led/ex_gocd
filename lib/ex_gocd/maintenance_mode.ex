defmodule ExGoCD.MaintenanceMode do
  @moduledoc """
  Server maintenance mode — pauses all pipeline scheduling when enabled.
  Mirrors GoCD's maintenance mode: pipelines in progress continue, new triggers
  and scheduling are blocked. Agents continue running existing jobs.
  """
  use GenServer

  # ── Client API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns true if maintenance mode is enabled."
  def enabled? do
    GenServer.call(__MODULE__, :enabled?)
  end

  @doc "Enables maintenance mode."
  def enable do
    GenServer.call(__MODULE__, :enable)
  end

  @doc "Disables maintenance mode."
  def disable do
    GenServer.call(__MODULE__, :disable)
  end

  @doc "Returns info about current maintenance mode state."
  def info do
    GenServer.call(__MODULE__, :info)
  end

  # ── Server Callbacks ───────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{enabled: false, enabled_at: nil, enabled_by: nil}}
  end

  @impl true
  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled, state}
  end

  @impl true
  def handle_call(:enable, _from, state) do
    if state.enabled do
      {:reply, {:error, :already_enabled}, state}
    else
      new_state = %{state | enabled: true, enabled_at: DateTime.utc_now(), enabled_by: "admin"}
      {:reply, {:ok, :enabled}, new_state}
    end
  end

  @impl true
  def handle_call(:disable, _from, state) do
    if not state.enabled do
      {:reply, {:error, :already_disabled}, state}
    else
      new_state = %{state | enabled: false, enabled_at: nil, enabled_by: nil}
      {:reply, {:ok, :disabled}, new_state}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply,
     %{
       enabled: state.enabled,
       enabled_at: state.enabled_at,
       enabled_by: state.enabled_by
     }, state}
  end
end
