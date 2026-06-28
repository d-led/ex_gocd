defmodule ExGoCD.DistSupervisor do
  @moduledoc """
  Starts singleton GenServers under Horde.DynamicSupervisor.
  """
  require Logger

  def start_singleton(child_module, args \\ []) do
    case Horde.DynamicSupervisor.start_child(
           ExGoCD.HordeSupervisor,
           {child_module, args}
         ) do
      {:ok, pid} ->
        Logger.debug("[DistSupervisor] #{child_module} started on #{node()}")
        {:ok, pid}

      {:ok, pid, _info} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("[DistSupervisor] #{child_module} on #{node(pid)} (not here)")
        {:ok, pid}

      {:error, _} = error ->
        Logger.warning("[DistSupervisor] #{child_module} start failed: #{inspect(error)}")
        error
    end
  end
end
