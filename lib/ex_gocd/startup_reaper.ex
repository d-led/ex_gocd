defmodule ExGoCD.StartupReaper do
  @moduledoc """
  Cluster-wide singleton (via Horde) that reconciles stale pipeline stages.

  Runs immediately on startup, then every 30 seconds. Only touches stages
  where ALL jobs are already Completed but the stage state was never
  transitioned — safe for in-flight jobs.

  Uses `DistSingleton` for cluster-singleton behavior: only one node in the
  cluster runs the reaper at any time.
  """
  use GenServer
  require Logger

  @reconcile_interval_ms 30_000

  # ── Public API ──────────────────────────────────────────────────────

  def start_link(_opts) do
    ExGoCD.DistSingleton.start_link(__MODULE__, [])
  end

  # ── Callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(_) do
    # Reconcile immediately on startup
    send(self(), :reconcile)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    count = ExGoCD.Pipelines.reconcile_stale_stages()

    if count > 0 do
      Logger.info("[StartupReaper] Fixed #{count} stale stage(s)")
    end

    Process.send_after(self(), :reconcile, @reconcile_interval_ms)
    {:noreply, state}
  end
end
