defmodule ExGoCD.AuditLog.Events do
  @moduledoc """
  Domain event factory for the audit log.

  **Every** audit event MUST be created through this module.
  No inline `AuditLog.log(...)` calls anywhere else.

  Each event has:
  - A unique `event_type` string (stored in the `action` column for indexing)
  - A versioned jsonb payload (stored in `details`) — `event_version` + `payload`
  - Metadata columns (`actor`, `resource_type`, `resource_name`) for direct queryability

  To add a new event type:
  1. Add a public function with typed parameters
  2. Call `emit/5` with the event_type, actor, resource metadata, and typed payload
  3. Bump `@event_version` if the payload schema changes (rare — prefer additive)
  """

  alias ExGoCD.AuditLog

  # ---------------------------------------------------------------------------
  # Event version — bump when the overall payload envelope changes
  # ---------------------------------------------------------------------------
  @event_version 1

  # ===========================================================================
  # Pipeline Events
  # ===========================================================================

  @doc """
  A pipeline was triggered (manual or auto).

  Payload: pipeline_name, counter
  """
  @spec pipeline_triggered(String.t(), String.t(), integer()) :: :ok
  def pipeline_triggered(actor, pipeline_name, counter) do
    emit("pipeline.triggered", actor, "pipeline", pipeline_name, %{
      counter: counter
    })
  end

  @doc """
  A pipeline was paused by an admin.

  Payload: pipeline_name, paused_by
  """
  @spec pipeline_paused(String.t(), String.t(), String.t()) :: :ok
  def pipeline_paused(actor, pipeline_name, paused_by) do
    emit("pipeline.paused", actor, "pipeline", pipeline_name, %{
      paused_by: paused_by
    })
  end

  @doc """
  A pipeline's pause state was toggled.

  Payload: pipeline_name, paused (boolean)
  """
  @spec pipeline_pause_toggled(String.t(), String.t(), boolean()) :: :ok
  def pipeline_pause_toggled(actor, pipeline_name, paused) do
    emit("pipeline.pause_toggled", actor, "pipeline", pipeline_name, %{
      paused: paused
    })
  end

  # ===========================================================================
  # Admin Events
  # ===========================================================================

  @doc """
  An admin cleaned up stuck (Scheduled/Building) jobs.

  Payload: count of cancelled jobs
  """
  @spec admin_cleanup_stuck_jobs(String.t(), non_neg_integer(), String.t() | nil) :: :ok
  def admin_cleanup_stuck_jobs(actor, count, remote_ip \\ nil) do
    emit(
      "admin.cleanup_stuck_jobs",
      actor,
      nil,
      nil,
      %{
        count: count
      },
      remote_ip
    )
  end

  @doc """
  An admin reset a pipeline (cleared its instances).

  Payload: pipeline_name
  """
  @spec admin_reset_pipeline(String.t(), String.t()) :: :ok
  def admin_reset_pipeline(actor, pipeline_name) do
    emit("admin.reset_pipeline", actor, "pipeline", pipeline_name, %{
      pipeline_name: pipeline_name
    })
  end

  # ===========================================================================
  # Agent Events
  # ===========================================================================

  @doc "An agent was enabled."
  @spec agent_enabled(String.t(), String.t()) :: :ok
  def agent_enabled(actor, agent_uuid) do
    emit("agent.enabled", actor, "agent", agent_uuid, %{})
  end

  @doc "An agent was disabled."
  @spec agent_disabled(String.t(), String.t()) :: :ok
  def agent_disabled(actor, agent_uuid) do
    emit("agent.disabled", actor, "agent", agent_uuid, %{})
  end

  @doc "An agent was deleted."
  @spec agent_deleted(String.t(), String.t()) :: :ok
  def agent_deleted(actor, agent_uuid) do
    emit("agent.deleted", actor, "agent", agent_uuid, %{})
  end

  @doc "All disabled agents were cleaned (soft-deleted)."
  @spec agents_cleaned_disabled(String.t(), integer()) :: :ok
  def agents_cleaned_disabled(actor, count) do
    emit("agent.clean_disabled", actor, nil, nil, %{count: count})
  end

  @doc "Agents were bulk-deleted."
  @spec agents_bulk_deleted(String.t(), integer()) :: :ok
  def agents_bulk_deleted(actor, count) do
    emit("agent.bulk_deleted", actor, nil, nil, %{count: count})
  end

  # ===========================================================================
  # Cancellation Events
  # ===========================================================================

  @doc "A stage was cancelled."
  @spec stage_cancelled(String.t(), String.t(), integer(), String.t(), String.t() | nil) :: :ok
  def stage_cancelled(actor, pipeline_name, pipeline_counter, stage_name, remote_ip \\ nil) do
    emit(
      "stage.cancelled",
      actor,
      "stage",
      "#{pipeline_name}/#{pipeline_counter}/#{stage_name}",
      %{
        pipeline_name: pipeline_name,
        pipeline_counter: pipeline_counter,
        stage_name: stage_name
      },
      remote_ip
    )
  end

  # ===========================================================================
  # Config Change Events
  # ===========================================================================

  @doc "Pipeline configuration was modified."
  @spec config_changed(String.t(), String.t(), map()) :: :ok
  def config_changed(actor, pipeline_name, diff) do
    emit("config.changed", actor, "pipeline", pipeline_name, %{diff: diff})
  end

  # ===========================================================================
  # Crash Events
  # ===========================================================================

  @doc "An unhandled server crash was captured."
  @spec server_crash(String.t(), map()) :: :ok
  def server_crash(source, details) do
    emit("server.crash", "system", source, nil, details)
  end

  # ===========================================================================
  # Private — single point of emission
  # ===========================================================================

  @doc false
  defp emit(event_type, actor, resource_type, resource_name, payload, remote_ip \\ nil) do
    details = %{
      event_version: @event_version,
      payload: payload
    }

    AuditLog.log(actor, event_type,
      resource_type: resource_type,
      resource_name: resource_name,
      details: details,
      remote_ip: remote_ip
    )
  end
end
