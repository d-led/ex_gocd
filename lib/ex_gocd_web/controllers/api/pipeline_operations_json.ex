defmodule ExGoCDWeb.API.PipelineOperationsJSON do
  def message(%{message: message}) do
    %{message: message}
  end

  def status(assigns) do
    %{
      paused: assigns.paused,
      paused_cause: assigns.paused_cause,
      paused_by: assigns.paused_by,
      locked: assigns.locked,
      schedulable: assigns.schedulable
    }
  end
end
