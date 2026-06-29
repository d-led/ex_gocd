defmodule ExGoCD.PluginNode do
  @moduledoc """
  Standalone plugin node — starts libcluster + a plugin GenServer on its own
  BEAM node. Joins the cluster, registers the plugin with Horde, and exposes
  its activity via a simple text UI on stdout.

  Usage:
    elixir --name plugin_observer@127.0.0.1 --cookie ex-gocd-demo-cookie \
      -S mix run -e 'ExGoCD.PluginNode.start()'
  """

  def start do
    IO.puts("=== Plugin Node starting ===")

    # Start required OTP apps
    Application.ensure_all_started(:libcluster)
    Application.ensure_all_started(:horde)
    Application.ensure_all_started(:jason)
    Application.ensure_all_started(:logger)

    # Start a minimal supervision tree
    children = [
      {Cluster.Supervisor, [topologies(), [name: :plugin_cluster_supervisor]]},
      # Register a simple observer GenServer that logs cluster events
      {ExGoCD.PluginNode.Observer, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

    IO.puts("=== Plugin Node: waiting for cluster connections ===")
    IO.puts("    node: #{inspect(Node.self())}")
    IO.puts("    cookie: #{inspect(Node.get_cookie())}")

    # Keep running
    Process.sleep(:infinity)
  end

  defp topologies do
    case System.get_env("ERLANG_SEED_NODES", "")
         |> String.split(",", trim: true)
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == ""))
         |> Enum.map(&String.to_atom/1) do
      [] -> [default: [strategy: Cluster.Strategy.Gossip]]
      seeds -> [default: [strategy: Cluster.Strategy.Epmd, config: [hosts: seeds]]]
    end
  end
end
