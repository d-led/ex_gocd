defmodule ExGoCD.PluginNode.Observer do
  @moduledoc """
  Simple observer GenServer for a standalone plugin node.
  Logs cluster join/leave events and polls the Plugin.Registry on connected
  server nodes to show what plugins are active.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :timer.send_interval(5000, :tick)
    {:ok, %{last_nodes: []}}
  end

  @impl true
  def handle_info(:tick, state) do
    current = Node.list()

    if current != state.last_nodes do
      joined = current -- state.last_nodes
      left = state.last_nodes -- current

      Enum.each(joined, &IO.puts("[plugin] 🟢 Node joined: #{inspect(&1)}"))
      Enum.each(left, &IO.puts("[plugin] 🔴 Node left: #{inspect(&1)}"))

      if current != [] do
        show_remote_plugins(current)
      end
    end

    {:noreply, %{state | last_nodes: current}}
  end

  defp show_remote_plugins(nodes) do
    Enum.each(nodes, fn node ->
      try do
        plugins = :rpc.call(node, ExGoCD.Plugin.Registry, :list, [])
        configured = Enum.reject(plugins, fn {_, mod} -> is_nil(mod) end)
        IO.puts("[plugin] #{inspect(node)} plugins: #{inspect(configured)}")
      catch
        _, _ -> IO.puts("[plugin] #{inspect(node)} not ready yet")
      end
    end)
  end
end
