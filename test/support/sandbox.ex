defmodule ExGoCD.Sandbox do
  @moduledoc """
  Hands a test's sandbox connection to the application's long-lived background
  processes.

  The application starts its singletons (scheduler, pollers, reaper, …) for
  every environment. They are started once, before any test runs, so they never
  belong to the process that owns a test's connection — without an explicit
  allowance their first query fails with `DBConnection.OwnershipError`.

  `allow/2` makes the named process borrow the connection owned by `owner`, so
  anything it reads or writes lands inside that test's transaction and is rolled
  back with it.

  Only the processes that a test may legitimately reach are listed. Periodic
  work that would fire on its own is switched off in `config/test.exs` instead,
  because it would run outside any transaction.
  """

  @background_processes [
    ExGoCD.MaintenanceMode,
    ExGoCD.Scheduler,
    ExGoCD.AgentRegistry,
    ExGoCD.Materials.Poller,
    ExGoCD.Materials.TimerScheduler,
    ExGoCD.Pipelines.ConsoleActivityMonitor,
    ExGoCD.SchedulingChecker.TriggerMonitor,
    ExGoCD.ElasticAgentScheduler,
    ExGoCD.DockerElasticAgentScheduler,
    ExGoCD.ConfigRepos.Poller,
    ExGoCD.Backup,
    ExGoCD.StartupReaper
  ]

  @spec allow_background_processes(pid()) :: :ok
  def allow_background_processes(owner) do
    Enum.each(@background_processes, &allow(owner, &1))
  end

  defp allow(owner, module) do
    case Process.whereis(module) do
      pid when is_pid(pid) and pid != owner ->
        Ecto.Adapters.SQL.Sandbox.allow(ExGoCD.Repo, owner, pid)

      _not_running ->
        :ok
    end
  end
end
