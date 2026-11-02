defmodule ExGoCD.StartupReaper do
  @moduledoc """
  Cluster-wide singleton (via Horde) that reconciles stale pipeline stages
  and agent states.

  Runs immediately on startup, then every 30 seconds.

  Reconciliation logic:
  - Stages with all jobs Completed → mark stage Completed
  - Agents in "Building" state with no active jobs → reset to "Idle"
    (handles server/agent restarts where state was not properly cleared)

  Uses `DistSingleton` for cluster-singleton behavior: only one node in the
  cluster runs the reaper at any time.
  """
  use GenServer
  require Logger

  import Ecto.Query, warn: false
  alias ExGoCD.Agents.Agent
  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.Repo

  @reconcile_interval_ms 30_000

  # ── Public API ──────────────────────────────────────────────────────

  def start_link(_opts) do
    ExGoCD.DistSingleton.start_link(__MODULE__, [])
  end

  # ── Callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(_) do
    # The periodic reconcile is background work. Tests switch it off and drive
    # the reconciliation functions directly, inside their own transaction.
    if Application.get_env(:ex_gocd, :startup_reaper_enabled, true) do
      send(self(), :reconcile)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    stage_count = ExGoCD.Pipelines.reconcile_stale_stages()
    agent_count = reconcile_agent_states()

    if stage_count + agent_count > 0 do
      Logger.info("[StartupReaper] Fixed #{stage_count} stale stage(s), #{agent_count} agent(s)")
    end

    Process.send_after(self(), :reconcile, @reconcile_interval_ms)
    {:noreply, state}
  end

  # ── Agent state reconciliation ──────────────────────────────────────

  @doc """
  Resets agents stuck in "Building" state when their assigned jobs are
  no longer active (Completed, Failed, Cancelled). Handles cases where
  server restarts or agent disconnects left agent state inconsistent.

  Returns count of agents reset.
  """
  def reconcile_agent_states do
    building_agents =
      Repo.all(from a in Agent, where: a.state == "Building" and a.deleted == false)

    Enum.reduce(building_agents, 0, fn agent, count ->
      count + revert_if_idle(agent)
    end)
  end

  # A restart takes the jobs with it, so an agent still marked building has nothing running.
  defp revert_if_idle(agent) do
    if agent_has_no_active_jobs?(agent.uuid) do
      agent
      |> Agent.changeset(%{state: "Idle"})
      |> Repo.update()
      |> reverted_count()
    else
      0
    end
  end

  defp reverted_count({:ok, _agent}), do: 1
  defp reverted_count({:error, _changeset}), do: 0

  defp agent_has_no_active_jobs?(agent_uuid) do
    active_states = ["Scheduled", "Assigned", "Preparing", "Building", "Completing"]

    count =
      Repo.aggregate(
        from(j in JobInstance,
          where: j.agent_uuid == ^agent_uuid and j.state in ^active_states
        ),
        :count
      )

    count == 0
  end
end
