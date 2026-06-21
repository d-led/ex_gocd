defmodule ExGoCD.VsmContextStore do
  @moduledoc """
  Stores OpenTelemetry span contexts keyed by build_id so that
  asynchronous agent status reports can continue the pipeline trace
  rather than creating orphan root spans.

  The context is captured in `scheduler.assign_work` (assign_and_send)
  and restored in `AgentJobRuns.report_status` / `Pipelines.complete_job_instance`.
  """

  @table_name :ex_gocd_vsm_contexts

  @doc "Creates the ETS table at app start. Idempotent."
  def setup do
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @doc "Stores the current OTel context for the given build_id."
  @spec put(String.t(), :otel_ctx.t()) :: true
  def put(build_id, ctx) when is_binary(build_id) do
    :ets.insert(@table_name, {build_id, ctx})
  end

  @doc "Retrieves and removes the stored context. Returns nil if not found."
  @spec take(String.t()) :: :otel_ctx.t() | nil
  def take(build_id) when is_binary(build_id) do
    case :ets.take(@table_name, build_id) do
      [{^build_id, ctx}] -> ctx
      [] -> nil
    end
  end
end
