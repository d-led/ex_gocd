defmodule ExGoCD.DistSingleton do
  @moduledoc """
  Cluster-wide singleton via Horde.Registry. Mirrors Ball pattern from ssr-robust-live-svg.
  """

  def via_horde(module) do
    {:via, Horde.Registry, {ExGoCD.HordeRegistry, module}}
  end

  def start_link(module, args) do
    case GenServer.start_link(module, args, name: via_horde(module)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> :ignore
    end
  end

  def whereis(module) do
    case Horde.Registry.lookup(ExGoCD.HordeRegistry, module) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
