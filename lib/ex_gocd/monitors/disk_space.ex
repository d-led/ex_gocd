# Copyright 2026 ex_gocd
# Disk space monitor — periodically checks artifact directory usage
# and pauses pipeline scheduling when disk is critically low.

defmodule ExGoCD.Monitors.DiskSpace do
  @moduledoc """
  Monitors disk space on the artifact storage directory.
  When free space drops below the critical threshold, pipeline scheduling
  is paused to prevent disk exhaustion.

  It reports what it measured and nothing else: `:unmeasured` until the first
  check, `:unknown` when the directory could not be read at all, and one of
  `:ok`, `:warning` or `:critical` once it has a number. There is no assumed
  amount of free space — a guess would hide exactly the disk this guard exists
  for.
  """
  use GenServer

  require Logger

  alias ExGoCD.PubSub
  alias ExGoCD.ServerConfig

  @monitor_topic "monitors:disk"

  # Default thresholds (bytes)
  # 500 MB
  @critical_threshold 500 * 1024 * 1024
  # 2 GB
  @warning_threshold 2 * 1024 * 1024 * 1024

  @type status :: :unmeasured | :ok | :warning | :critical | :unknown

  # ── Client API ──────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    ExGoCD.DistSingleton.start_link(__MODULE__, opts)
  end

  @doc """
  The last measurement: `:unmeasured` before the first check, `:unknown` when
  the artifact directory could not be read, otherwise the space it found.
  """
  @spec status() :: status()
  def status, do: call(:status, :unmeasured)

  @doc """
  Measures now and answers the status, for a caller that cannot wait for the
  timer.
  """
  @spec check_now() :: status()
  def check_now, do: call(:check, :unmeasured)

  @doc """
  Subscribes to disk monitor updates (topic `monitors:disk`).
  """
  def subscribe do
    Phoenix.PubSub.subscribe(PubSub, @monitor_topic)
  end

  defp call(message, when_absent) do
    case ExGoCD.DistSingleton.whereis(__MODULE__) do
      nil -> when_absent
      pid -> GenServer.call(pid, message)
    end
  end

  # ── Server ──────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    interval = Application.get_env(:ex_gocd, :disk_monitor_interval, 60_000)

    # `:none` is how this project switches a timer off in tests: a check reads
    # the stored artifacts directory, a database read, and a supervised process
    # must not make one outside a test's sandbox transaction.
    if interval != :none do
      send(self(), :check)
    end

    {:ok, %{status: :unmeasured, free_bytes: nil, interval: interval}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:check, _from, state) do
    state = measure(state)
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(:check, %{interval: :none} = state), do: {:noreply, state}

  def handle_info(:check, state) do
    state = measure(state)
    Process.send_after(self(), :check, state.interval)
    {:noreply, state}
  end

  defp measure(state) do
    free_bytes = free_disk_space(ServerConfig.artifacts_dir())
    new_status = status_for(free_bytes)

    if new_status != state.status do
      Logger.warning(
        "Disk monitor: #{state.status} → #{new_status} (free: #{format_bytes(free_bytes)})"
      )

      Phoenix.PubSub.broadcast(PubSub, @monitor_topic, {:disk_status, new_status, free_bytes})
    end

    %{state | status: new_status, free_bytes: free_bytes}
  end

  # `df` prints the free space of the filesystem the path lives on. A path it
  # cannot read answers with a non-zero status, which is "not known", not
  # "empty" and not "plenty".
  defp free_disk_space(path) do
    case System.cmd("df", [path], stderr_to_stdout: true) do
      {output, 0} -> available_bytes(output)
      _ -> nil
    end
  end

  defp available_bytes(output) do
    output
    |> String.split("\n")
    |> Enum.at(1)
    |> kilobytes_in_available_column()
  end

  # df prints a header line and then the row; "Available" is its fourth column,
  # in 1K blocks.
  defp kilobytes_in_available_column(nil), do: nil

  defp kilobytes_in_available_column(line) do
    line
    |> String.split(~r/\s+/, trim: true)
    |> Enum.at(3)
    |> kilobytes_to_bytes()
  end

  defp kilobytes_to_bytes(nil), do: nil

  defp kilobytes_to_bytes(available) do
    case Integer.parse(available) do
      {kilobytes, _} -> kilobytes * 1024
      :error -> nil
    end
  end

  defp status_for(nil), do: :unknown
  defp status_for(free) when free < @critical_threshold, do: :critical
  defp status_for(free) when free < @warning_threshold, do: :warning
  defp status_for(_free), do: :ok

  defp format_bytes(nil), do: "unknown"

  defp format_bytes(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{bytes} B"
    end
  end
end
