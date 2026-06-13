# Copyright 2026 ex_gocd
# Console inactivity monitor that detects and cancels hung agent builds.

defmodule ExGoCD.Pipelines.ConsoleActivityMonitor do
  @moduledoc """
  GenServer that periodically monitors running job runs.
  If a running job's console log has not been updated (no console append activity)
  for longer than the configured timeout duration, the build is cancelled on the agent
  and marked as Completed/Cancelled on the server.
  """
  use GenServer
  import Ecto.Query

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Repo
  alias ExGoCDWeb.AgentChannel

  require Logger

  # Check interval in milliseconds (default: 10 seconds)
  @check_interval_ms 10_000
  # Default console inactivity timeout (default: 900 seconds / 15 minutes)
  @default_timeout_sec 900

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_activity, state) do
    _ = safe_db(&check_active_runs/0, :ok)
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    interval = Application.get_env(:ex_gocd, :console_monitor_interval_ms, @check_interval_ms)
    if interval != :none do
      Process.send_after(self(), :check_activity, interval)
    end
  end

  @doc """
  Runs a scan of active job runs and cancels those exceeding their inactivity limit.
  """
  def check_active_runs do
    active_runs =
      AgentJobRun
      |> where([r], r.state in ["Assigned", "Building", "Completing"])
      |> Repo.all()
      |> Repo.preload(job_instance: :job)

    now = DateTime.utc_now()
    Enum.each(active_runs, &check_run_inactivity(&1, now))

    :ok
  end

  defp check_run_inactivity(run, now) do
    case get_timeout_seconds(run) do
      :never ->
        :ok

      timeout_sec when is_integer(timeout_sec) ->
        elapsed_sec = DateTime.diff(now, run.updated_at, :second)
        maybe_cancel_run(run, elapsed_sec, timeout_sec)
    end
  end

  defp maybe_cancel_run(run, elapsed_sec, timeout_sec) do
    if elapsed_sec > timeout_sec do
      Logger.warning("Job run #{run.build_id} (agent #{run.agent_uuid}) is cancelled due to console inactivity of #{elapsed_sec} seconds (timeout: #{timeout_sec} seconds).")
      _ = AgentChannel.request_cancel_build(run.agent_uuid, run.build_id)
      _ = AgentJobRuns.report_status(run.agent_uuid, run.build_id, "Completed", "Cancelled")
    end
  end

  defp get_timeout_seconds(run) do
    job_timeout =
      case run.job_instance do
        %{job: %{timeout: timeout}} when is_binary(timeout) ->
          parse_timeout(timeout)

        _ ->
          nil
      end

    job_timeout || get_default_timeout()
  end

  defp parse_timeout(timeout) when is_binary(timeout) do
    case String.downcase(timeout) do
      "never" ->
        :never

      val ->
        case Integer.parse(val) do
          {mins, _} -> mins * 60
          :error -> nil
        end
    end
  end

  defp get_default_timeout do
    case System.get_env("EX_GOCD_DEFAULT_CONSOLE_TIMEOUT_SEC") do
      nil ->
        Application.get_env(:ex_gocd, :default_console_timeout_sec, @default_timeout_sec)

      val ->
        case Integer.parse(val) do
          {num, _} -> num
          :error -> @default_timeout_sec
        end
    end
  end

  # Safe DB execution helper to prevent Sandbox crashes in test mode or before DB boots
  defp safe_db(fun, fallback) do
    fun.()
  rescue
    _ -> fallback
  catch
    _, _ -> fallback
  end
end
