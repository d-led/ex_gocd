defmodule ExGoCD.SchedulingChecker.TriggerMonitor do
  @moduledoc """
  In-memory dedup set for pipeline triggers.

  Mirrors GoCD's `TriggerMonitor` which uses a `ConcurrentSkipListSet`
  to track pipelines currently being triggered. Prevents duplicate
  triggers when multiple requests arrive in rapid succession.

  Uses an ETS set for O(1) membership check and atomic insert.
  The ETS table is lazily created on first use so tests don't break.
  """
  use GenServer

  @table_name :ex_gocd_trigger_monitor

  # ── Client API ──────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if this pipeline is already being triggered.
  """
  @spec already_triggered?(String.t()) :: boolean()
  def already_triggered?(pipeline_name) when is_binary(pipeline_name) do
    ensure_table!()
    case :ets.lookup(@table_name, pipeline_name) do
      [] -> false
      _ -> true
    end
  end

  @doc """
  Marks a pipeline as currently being triggered. Returns true if it was
  NOT already in the set (i.e., this is the first trigger).
  """
  @spec mark_triggered(String.t()) :: boolean()
  def mark_triggered(pipeline_name) when is_binary(pipeline_name) do
    ensure_table!()
    :ets.insert_new(@table_name, {pipeline_name})
  end

  @doc """
  Removes a pipeline from the triggered set.
  """
  @spec mark_completed(String.t()) :: :ok
  def mark_completed(pipeline_name) when is_binary(pipeline_name) do
    ensure_table!()
    :ets.delete(@table_name, pipeline_name)
    :ok
  end

  # ── Server ──────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    ensure_table!()
    {:ok, %{}}
  end

  defp ensure_table! do
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    end
    :ok
  end
end
