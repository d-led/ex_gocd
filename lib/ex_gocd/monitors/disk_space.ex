# Copyright 2026 ex_gocd
# Disk space monitor — periodically checks artifact directory usage
# and pauses pipeline scheduling when disk is critically low.

defmodule ExGoCD.Monitors.DiskSpace do
  @moduledoc """
  Monitors disk space on the artifact storage directory.
  When free space drops below the critical threshold, pipeline scheduling
  is paused to prevent disk exhaustion.
  """
  use GenServer

  require Logger

  alias ExGoCD.PubSub

  @monitor_topic "monitors:disk"

  # Default thresholds (bytes)
  # 500 MB
  @critical_threshold 500 * 1024 * 1024
  # 2 GB
  @warning_threshold 2 * 1024 * 1024 * 1024

  # ── Client API ──────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    ExGoCD.DistSingleton.start_link(__MODULE__, opts)
  end

  @doc """
  Returns the current disk status: :ok, :warning, or :critical.
  """
  def status do
    GenServer.call(ExGoCD.DistSingleton.via_horde(__MODULE__), :status)
  end

  @doc """
  Subscribes to disk monitor updates (topic `monitors:disk`).
  """
  def subscribe do
    Phoenix.PubSub.subscribe(PubSub, @monitor_topic)
  end

  # ── Server ──────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    interval = Application.get_env(:ex_gocd, :disk_monitor_interval, 60_000)
    send(self(), :check)
    {:ok, %{status: :ok, free_bytes: nil, interval: interval}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(:check, state) do
    new_state = perform_check(state)
    Process.send_after(self(), :check, state.interval)
    {:noreply, new_state}
  end

  defp perform_check(state) do
    artifact_dir = Application.get_env(:ex_gocd, :artifact_dir, "artifacts")

    free_bytes = free_disk_space(artifact_dir)

    new_status = compute_status(free_bytes)

    if new_status != state.status do
      Logger.warning(
        "Disk monitor: #{state.status} → #{new_status} (free: #{format_bytes(free_bytes)})"
      )

      Phoenix.PubSub.broadcast(PubSub, @monitor_topic, {:disk_status, new_status, free_bytes})
    end

    %{state | status: new_status, free_bytes: free_bytes}
  end

  # Returns available disk space for the filesystem containing path.
  # Falls back to 10 GB if path doesn't exist or stat fails.
  defp free_disk_space(path) do
    case File.stat(path) do
      {:ok, _} ->
        # Approximate: check parent directory or path itself
        # Using a simple approach: stat the path, estimate from system
        # In production, use :erlang.system_info or OS-specific calls
        _estimate_free(path)

      {:error, _} ->
        # Assume 10 GB available
        10 * 1024 * 1024 * 1024
    end
  end

  # Crude free-space estimate using filesystem info
  defp _estimate_free(path) do
    # Try to get disk info via OS command (safe fallback if it fails)
    case System.cmd("df", [path], stderr_to_stdout: true) do
      {output, 0} ->
        parse_df_output(output)

      _ ->
        10 * 1024 * 1024 * 1024
    end
  end

  defp parse_df_output(output) do
    output
    |> String.split("\n")
    |> Enum.at(1)
    |> case do
      nil ->
        nil

      line ->
        parts = String.split(line, ~r/\s+/, trim: true)
        # df output: Filesystem 1K-blocks Used Available ...
        # Available is typically column 4 (0-indexed: 3)
        case Enum.at(parts, 3) do
          nil ->
            nil

          avail_str ->
            case Integer.parse(avail_str) do
              # Convert 1K blocks to bytes
              {n, _} -> n * 1024
              :error -> nil
            end
        end
    end
  end

  defp compute_status(nil), do: :ok
  defp compute_status(free) when free < @critical_threshold, do: :critical
  defp compute_status(free) when free < @warning_threshold, do: :warning
  defp compute_status(_), do: :ok

  defp format_bytes(nil), do: "unknown"

  defp format_bytes(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{bytes} B"
    end
  end
end
