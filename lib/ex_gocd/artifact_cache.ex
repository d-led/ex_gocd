defmodule ExGoCD.ArtifactCache do
  @moduledoc """
  Server-side zip artifact cache. Read-path optimization — GoCD ZipArtifactCache parity.

  When a directory is requested as `.zip`, the first request creates a cached zip.
  Subsequent requests serve from cache. Cache is invalidated when new artifacts
  are uploaded to the same stage.

  ## Configuration
    - `EX_GOCD_ARTIFACT_CACHE_SIZE_MB` — max cache size (default 200MB)
    - `EX_GOCD_ARTIFACT_CACHE_ENABLED` — toggle (default true)
  """
  use GenServer
  require Logger

  @cache_dir "tmp/artifact_cache"
  @max_size_mb (case Integer.parse(System.get_env("EX_GOCD_ARTIFACT_CACHE_SIZE_MB", "200")) do
                  {n, _} -> n
                  :error -> 200
                end)
  @cleanup_interval_ms 300_000

  # ── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get cached zip path for a directory, or nil if not cached."
  def get(dir_path) do
    GenServer.call(__MODULE__, {:get, dir_path})
  end

  @doc "Store a zip for a directory in the cache."
  def put(dir_path, zip_path) do
    GenServer.cast(__MODULE__, {:put, dir_path, zip_path})
  end

  @doc "Invalidate all cached entries for a stage."
  def invalidate_stage(pipeline, counter, stage, stage_counter) do
    GenServer.cast(__MODULE__, {:invalidate_stage, pipeline, counter, stage, stage_counter})
  end

  @doc "Return cache stats: size, count, last cleanup."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Clear the entire cache."
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # ── Server callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    File.mkdir_p!(@cache_dir)
    schedule_cleanup()
    {:ok, %{entries: %{}, total_bytes: 0, last_cleanup: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:get, dir_path}, _from, state) do
    key = cache_key(dir_path)
    entry = Map.get(state.entries, key)
    {:reply, entry && File.exists?(entry.zip_path) && entry.zip_path, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       entry_count: map_size(state.entries),
       total_mb: Float.round(state.total_bytes / 1_048_576, 2),
       last_cleanup: state.last_cleanup
     }, state}
  end

  def handle_call(:clear, _from, _state) do
    File.rm_rf!(@cache_dir)
    File.mkdir_p!(@cache_dir)
    {:reply, :ok, %{entries: %{}, total_bytes: 0, last_cleanup: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:put, dir_path, zip_path}, state) do
    key = cache_key(dir_path)

    size =
      case File.stat(zip_path) do
        {:ok, stat} -> stat.size
        _ -> 0
      end

    entry = %{zip_path: zip_path, size: size, created_at: DateTime.utc_now()}

    {:noreply,
     %{state | entries: Map.put(state.entries, key, entry), total_bytes: state.total_bytes + size}}
  end

  def handle_cast({:invalidate_stage, pipeline, counter, stage, stage_counter}, state) do
    prefix = "#{pipeline}/#{counter}/#{stage}/#{stage_counter}/"

    {to_remove, remaining} =
      Enum.split_with(state.entries, fn {key, _entry} ->
        String.starts_with?(key, prefix)
      end)

    freed =
      Enum.reduce(to_remove, 0, fn {_key, entry}, acc ->
        File.rm(entry.zip_path)
        acc + entry.size
      end)

    Logger.debug(
      "[ArtifactCache] Invalidated #{length(to_remove)} entries (#{Float.round(freed / 1_048_576, 2)}MB) for #{prefix}"
    )

    {:noreply, %{state | entries: Map.new(remaining), total_bytes: state.total_bytes - freed}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    schedule_cleanup()
    {:noreply, enforce_max_size(state)}
  end

  # ── Internal ─────────────────────────────────────────────────────────────

  defp cache_key(dir_path) do
    dir_path
    |> String.replace(~r/^#{Regex.escape(artifacts_dir())}\//, "")
    |> String.trim_trailing("/")
  end

  defp artifacts_dir do
    System.get_env("ARTIFACTS_DIR") || "artifacts"
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp enforce_max_size(state) do
    if state.total_bytes > @max_size_mb * 1_048_576 do
      # Evict oldest entries (LRU) until under limit
      sorted = Enum.sort_by(state.entries, fn {_k, v} -> v.created_at end, DateTime)

      {to_evict, remaining, freed} =
        Enum.reduce_while(sorted, {[], state.total_bytes, 0}, fn {key, entry},
                                                                 {evicted, total, freed} ->
          if total - entry.size <= @max_size_mb * 1_048_576 do
            {:halt, {evicted, total, freed}}
          else
            File.rm(entry.zip_path)
            {:cont, {[{key, entry} | evicted], total - entry.size, freed + entry.size}}
          end
        end)

      Logger.info(
        "[ArtifactCache] LRU eviction: removed #{length(to_evict)} entries (#{Float.round(freed / 1_048_576, 2)}MB)"
      )

      %{
        state
        | entries: Map.drop(state.entries, Enum.map(to_evict, &elem(&1, 0))),
          total_bytes: remaining
      }
    else
      state
    end
  end
end
