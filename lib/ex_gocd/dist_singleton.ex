defmodule ExGoCD.DistSingleton do
  @moduledoc """
  Cluster-wide singleton helpers via Horde.Registry.

  Falls back to local name when Horde registry is not running (test).
  """

  def via_horde(module) do
    if horde_ready?() do
      {:via, Horde.Registry, {ExGoCD.HordeRegistry, module}}
    else
      module
    end
  end

  def call(module, msg, timeout \\ 5000) do
    GenServer.call(via_horde(module), msg, timeout)
  end

  def cast(module, msg) do
    GenServer.cast(via_horde(module), msg)
  end

  def whereis(module) do
    if horde_ready?() do
      case Horde.Registry.lookup(ExGoCD.HordeRegistry, module) do
        [{pid, _}] -> pid
        [] -> nil
      end
    else
      Process.whereis(module)
    end
  end

  defp horde_ready?, do: Process.whereis(ExGoCD.HordeRegistry) != nil
end
