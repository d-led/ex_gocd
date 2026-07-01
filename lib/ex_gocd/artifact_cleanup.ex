# Copyright 2026 ex_gocd
# Artifact rotation & cleanup — mirrors GoCD's purge logic with explicit
# "keep last N runs per stage" retention (not in original GoCD source).

defmodule ExGoCD.ArtifactCleanup do
  @moduledoc """
  Manages artifact storage: size-based purge, age-based purge, per-stage
  retention count, never_cleanup_artifacts flag, and a global on/off toggle.

  Two triggers:
    - On-upload: `cleanup_if_needed/0` called by ArtifactsController
    - Periodic:  GenServer runs `cleanup_if_needed/0` every 5 minutes

  Protection order (earlier = stronger):
    1. Global toggle OFF        → nothing deleted
    2. never_cleanup_artifacts  → stage's artifacts never deleted
    3. Retention runs (N)       → keep artifacts from last N pipeline runs
    4. Age threshold            → only delete if older than max_age_days
    5. Size limit               → delete oldest-first until under limit
  """
  use GenServer

  import Ecto.Query
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance, StageInstance}
  alias ExGoCD.Repo

  require Logger

  @default_max_size_mb 500
  @default_max_age_days 0
  @default_cleanup_interval_ms 300_000

  # ═══════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════

  @doc "Per-node GenServer entry point (one per node, NOT Horde singleton)."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Runs the cleanup check: size-based, age-based, respecting all protections.
  Returns :ok (always — failures are logged, never crash the caller).
  """
  @spec cleanup_if_needed :: :ok
  def cleanup_if_needed do
    unless cleanup_enabled?() do
      Logger.debug("Artifact cleanup disabled via EX_GOCD_ARTIFACT_CLEANUP_ENABLED")
      :ok
    else
      artifacts_path = artifacts_dir()

      if File.exists?(artifacts_path) do
        run_cleanup(artifacts_path)
      else
        :ok
      end
    end
  end

  @doc """
  Returns the recursive size of a file or directory in bytes.
  """
  @spec get_dir_size(String.t()) :: non_neg_integer()
  def get_dir_size(path) do
    if File.dir?(path) do
      dir_contents_size(path)
    else
      file_size(path)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # GenServer callbacks
  # ═══════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    interval = env_int("EX_GOCD_CLEANUP_INTERVAL_MS", @default_cleanup_interval_ms)
    schedule_check(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:cleanup_check, state) do
    cleanup_if_needed()
    schedule_check(state.interval)
    {:noreply, state}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :cleanup_check, interval)
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Core cleanup logic
  # ═══════════════════════════════════════════════════════════════════════

  defp run_cleanup(artifacts_path) do
    current_size = get_dir_size(artifacts_path)
    limit_bytes = limit_bytes()
    max_age_days = max_age_days()

    Logger.debug(
      "Cleanup check: size=#{current_size}B limit=#{limit_bytes}B age_limit=#{max_age_days}d"
    )

    cond do
      # Age-based: delete anything older than max_age_days (if configured > 0)
      max_age_days > 0 ->
        age_seconds = round(max_age_days * 86_400)
        age_cutoff = DateTime.add(DateTime.utc_now(), -age_seconds, :second)
        Logger.info("Age-based cleanup: deleting artifacts older than #{max_age_days} days")
        purge_by_age(age_cutoff)

      # Size-based: delete oldest first until under limit
      current_size > limit_bytes ->
        Logger.info(
          "Size-based cleanup: #{current_size}B exceeds #{limit_bytes}B limit"
        )

        purge_old_artifacts(current_size - limit_bytes)

      true ->
        :ok
    end

    :ok
  end

  # ── Size-based purge ───────────────────────────────────────────────

  defp purge_old_artifacts(bytes_to_free) do
    completed_stages = fetch_completed_stages()

    Enum.reduce_while(completed_stages, bytes_to_free, fn si, remaining ->
      if remaining <= 0, do: {:halt, remaining}, else: purge_if_unprotected(si, remaining)
    end)
  end

  # ── Age-based purge ────────────────────────────────────────────────

  defp purge_by_age(age_cutoff) do
    stages =
      StageInstance
      |> where(state: "Completed", artifacts_deleted: false)
      |> where([si], si.completed_at < ^age_cutoff)
      |> order_by(asc: :completed_at)
      |> Repo.all()
      |> Repo.preload(pipeline_instance: [pipeline: :stages])

    Enum.each(stages, fn si ->
      {:cont, _} = purge_if_unprotected(si, :ignore_size)
    end)

    :ok
  end

  # ── Shared: fetch & protect & delete ───────────────────────────────

  defp fetch_completed_stages do
    StageInstance
    |> where(state: "Completed", artifacts_deleted: false)
    |> order_by(asc: :completed_at)
    |> Repo.all()
    |> Repo.preload(pipeline_instance: [pipeline: :stages])
  end

  defp purge_if_unprotected(si, remaining_or_atom) do
    pipeline_instance = si.pipeline_instance
    pipeline = pipeline_instance.pipeline

    cond do
      never_cleanup?(pipeline, si.name) ->
        {:cont, remaining_or_atom}

      within_retention_runs?(pipeline, si) ->
        {:cont, remaining_or_atom}

      true ->
        delete_and_mark(si, pipeline, pipeline_instance, remaining_or_atom)
    end
  end

  defp delete_and_mark(si, pipeline, pipeline_instance, remaining_or_atom) do
    stage_dir = stage_artifact_dir(pipeline, pipeline_instance, si)

    # ── Atomicity (GoCD pattern) ──────────────────────────────────
    # Mark as deleted in DB FIRST — this is the single source of truth.
    # If an agent requests this artifact after this point, the controller
    # sees artifacts_deleted=true and returns 410 Gone, even if the files
    # are still momentarily on disk.  File deletion happens below; failure
    # to delete is logged but the artifact remains "unavailable" to agents.
    si
    |> StageInstance.changeset(%{artifacts_deleted: true})
    |> Repo.update!()

    size = get_dir_size(stage_dir)

    # sobelow_skip ["Traversal.FileModule"]
    case File.rm_rf(stage_dir) do
      {:ok, _} ->
        Logger.info(
          "Purged artifacts: #{pipeline.name}/#{pipeline_instance.counter}/" <>
            "#{si.name}/#{si.counter} (#{size}B freed)"
        )

      {:error, reason, _file} ->
        Logger.error(
          "Failed to delete #{stage_dir} after marking as purged: #{inspect(reason)}. " <>
            "Files may remain on disk but DB flag is set — artifact is unavailable to agents."
        )
    end

    case remaining_or_atom do
      :ignore_size -> {:cont, :ignore_size}
      remaining -> {:cont, remaining - size}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Protection predicates
  # ═══════════════════════════════════════════════════════════════════════

  defp never_cleanup?(%Pipeline{stages: stages}, stage_name) do
    case Enum.find(stages || [], &(&1.name == stage_name)) do
      nil -> false
      stage_config -> stage_config.never_cleanup_artifacts
    end
  end

  # Keep last N runs: queries stage instances for this
  # (pipeline_id, stage_name), sorted by (counter DESC), takes top N.
  defp within_retention_runs?(%Pipeline{id: pipeline_id, stages: stages}, si) do
    n = retention_n(stages, si.name)

    if n <= 0 do
      false
    else
      recent =
        StageInstance
        |> where(state: "Completed", artifacts_deleted: false, name: ^si.name)
        |> join(:inner, [si2], pi in PipelineInstance, on: si2.pipeline_instance_id == pi.id)
        |> where([_si2, pi], pi.pipeline_id == ^pipeline_id)
        |> order_by([_si2, pi], desc: pi.counter, desc: :counter)
        |> limit(^n)
        |> select([si2, _pi], si2.id)
        |> Repo.all()

      si.id in recent
    end
  end

  defp retention_n(stages, stage_name) do
    case Enum.find(stages || [], &(&1.name == stage_name)) do
      nil -> 1
      stage_config -> stage_config.artifact_retention_runs || 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════════════

  defp stage_artifact_dir(pipeline, pipeline_instance, si) do
    Path.expand(
      Path.join([
        artifacts_dir(),
        pipeline.name,
        to_string(pipeline_instance.counter),
        si.name,
        to_string(si.counter)
      ])
    )
  end

  # ── Config ──────────────────────────────────────────────────────────

  defp cleanup_enabled? do
    System.get_env("EX_GOCD_ARTIFACT_CLEANUP_ENABLED", "true") == "true"
  end

  defp limit_bytes do
    env_int("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", @default_max_size_mb) * 1024 * 1024
  end

  defp max_age_days do
    env_num("EX_GOCD_MAX_ARTIFACT_AGE_DAYS", @default_max_age_days)
  end

  defp env_num(key, default) do
    case System.get_env(key) do
      nil ->
        Application.get_env(:ex_gocd, String.to_atom(String.downcase(key)), default)

      val ->
        case Float.parse(val) do
          {n, _} -> n
          :error -> default
        end
    end
  end

  defp env_int(key, default) do
    case System.get_env(key) do
      nil ->
        Application.get_env(:ex_gocd, String.to_atom(String.downcase(key)), default)

      val ->
        case Integer.parse(val) do
          {n, _} -> n
          :error -> default
        end
    end
  end

  defp artifacts_dir do
    System.get_env("ARTIFACTS_DIR") || "artifacts"
  end

  # ── File system ─────────────────────────────────────────────────────

  defp dir_contents_size(path) do
    case File.ls(path) do
      {:ok, names} ->
        Enum.reduce(names, 0, fn name, acc ->
          acc + get_dir_size(Path.join(path, name))
        end)

      _ ->
        0
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      _ -> 0
    end
  end
end
