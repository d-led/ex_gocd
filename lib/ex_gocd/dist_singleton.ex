defmodule ExGoCD.DistSingleton do
  @moduledoc """
  Cluster-wide singleton support via Horde.Registry.

  Falls back to local name registration when Horde is not running (test).
  """

  def via_horde(module) do
    if horde_ready?() do
      {:via, Horde.Registry, {ExGoCD.HordeRegistry, module}}
    else
      module
    end
  end

  def start_link(module, args, gen_server_opts \\ []) do
    opts = Keyword.put(gen_server_opts, :name, via_horde(module))

    case GenServer.start_link(module, args, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> :ignore
      other -> other
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
