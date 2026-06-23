defmodule ExGoCD.SchedulingChecker.AboutToBeTriggered do
  @moduledoc """
  Debounce checker: prevents triggering a pipeline that is already
  in the process of being triggered.

  Mirrors GoCD's `AboutToBeTriggeredChecker`. Uses the ETS-based
  `TriggerMonitor` for O(1) lookups with no DB queries.
  """
  use ExGoCD.SchedulingChecker

  alias ExGoCD.SchedulingChecker.TriggerMonitor

  @impl true
  def check(pipeline_name) do
    if TriggerMonitor.already_triggered?(pipeline_name) do
      {:error, :already_triggered}
    else
      :ok
    end
  end
end
