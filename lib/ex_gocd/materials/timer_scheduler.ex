# Copyright 2026 ex_gocd
# Fires cron-scheduled pipeline triggers, mirroring GoCD's TimerScheduler.
# Each pipeline with a non-nil `timer` field registers a recurring Process.send_after loop.
# On each tick the scheduler calls Pipelines.trigger_pipeline/1 (with optional onlyOnChanges guard).
# Timers are refreshed whenever pipelines:updates is broadcast (config change, new pipeline, etc.).

defmodule ExGoCD.Materials.TimerScheduler do
  @moduledoc """
  Cron-based pipeline trigger service.

  Reads all pipeline configs with a `timer` cron spec on startup and after any
  `pipelines:updates` broadcast, then fires `Pipelines.trigger_pipeline/1` at the
  appropriate wall-clock times.

  Timer spec format: standard 6-field Quartz cron (`"0 0 22 ? * MON-FRI"`).
  When `timer_only_on_changes: true` the trigger is skipped if no new SCM modification
  has arrived since the last successful run of this pipeline.
  """
  use GenServer
  require Logger

  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  import Ecto.Query

  # Interval between cron evaluation checks (every 60 seconds).
  @tick_ms 60_000

  # ── Client API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return the names of all currently scheduled pipelines (for testing)."
  def scheduled_pipelines do
    GenServer.call(__MODULE__, :scheduled_pipelines)
  end

  # ── Server callbacks ─────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExGoCD.PubSub, "pipelines:updates")
    send(self(), :reload_timers)
    {:ok, %{timers: %{}}}
  end

  @impl true
  def handle_call(:scheduled_pipelines, _from, state) do
    {:reply, Map.keys(state.timers), state}
  end

  @impl true
  def handle_info(:reload_timers, state) do
    state = cancel_all_timers(state)
    timers = load_and_schedule_all()
    {:noreply, %{state | timers: timers}}
  end

  def handle_info(:pipelines_updated, state) do
    # Re-read config after any pipeline config change.
    send(self(), :reload_timers)
    {:noreply, state}
  end

  def handle_info({:timer_tick, pipeline_name}, state) do
    maybe_trigger(pipeline_name)
    # Re-schedule for the next tick.
    ref = schedule_tick(pipeline_name)
    {:noreply, put_in(state, [:timers, pipeline_name], ref)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp load_and_schedule_all do
    timer_pipelines()
    |> Enum.reduce(%{}, fn pipeline, acc ->
      ref = schedule_tick(pipeline.name)
      Map.put(acc, pipeline.name, ref)
    end)
  end

  defp timer_pipelines do
    safe_db(fn ->
      Repo.all(from p in Pipelines.Pipeline, where: not is_nil(p.timer))
    end) || []
  end

  defp schedule_tick(pipeline_name) do
    Process.send_after(self(), {:timer_tick, pipeline_name}, @tick_ms)
  end

  defp cancel_all_timers(state) do
    Enum.each(state.timers, fn {_name, ref} -> Process.cancel_timer(ref) end)
    %{state | timers: %{}}
  end

  defp maybe_trigger(pipeline_name) do
    pipeline = safe_db(fn -> Pipelines.get_pipeline_by_name(pipeline_name) end)

    case pipeline do
      nil ->
        Logger.debug("[TimerScheduler] Pipeline #{pipeline_name} no longer exists — dropping timer")

      %{timer: nil} ->
        Logger.debug("[TimerScheduler] Pipeline #{pipeline_name} timer removed — dropping tick")

      %{timer_only_on_changes: true} = p ->
        if has_new_modifications_since_last_run?(p) do
          do_trigger(pipeline_name)
        else
          Logger.debug("[TimerScheduler] #{pipeline_name}: skipping timer — no new material changes")
        end

      _p ->
        do_trigger(pipeline_name)
    end
  end

  defp do_trigger(pipeline_name) do
    Logger.info("[TimerScheduler] Firing scheduled trigger for pipeline: #{pipeline_name}")

    case Pipelines.trigger_pipeline(pipeline_name) do
      {:ok, instance} ->
        Logger.info("[TimerScheduler] #{pipeline_name} triggered → instance ##{instance.counter}")

      {:error, reason} ->
        Logger.warning("[TimerScheduler] #{pipeline_name} could not be triggered: #{inspect(reason)}")
    end
  end

  defp has_new_modifications_since_last_run?(pipeline) do
    last_run_time = safe_db(fn -> last_successful_run_time(pipeline.id) end)

    case last_run_time do
      nil ->
        # Never ran — allow first timer run.
        true

      run_time ->
        safe_db(fn ->
          alias ExGoCD.Pipelines.{Material, Modification}

          Repo.exists?(
            from m in Modification,
              join: mat in Material,
              on: mat.id == m.material_id,
              join: pm in "pipelines_materials",
              on: pm.material_id == mat.id and pm.pipeline_id == ^pipeline.id,
              where: m.modified_time > ^run_time
          )
        end) || false
    end
  end

  defp last_successful_run_time(pipeline_id) do
    alias ExGoCD.Pipelines.{PipelineInstance, StageInstance}

    Repo.one(
      from pi in PipelineInstance,
        join: si in StageInstance,
        on: si.pipeline_instance_id == pi.id,
        where: pi.pipeline_id == ^pipeline_id and si.result == "Passed",
        select: max(si.completed_at),
        limit: 1
    )
  end

  defp safe_db(fun) do
    try do
      fun.()
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end
end
