defmodule ExGoCD.PluginNodeTest do
  @moduledoc """
  A plugin node only has one decision of its own: how it finds the other nodes.
  Everything else is libcluster and a GenServer that prints.

  The decision reads the environment, so this file runs alone.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.PluginNode

  setup do
    previous = System.get_env("ERLANG_SEED_NODES")
    on_exit(fn -> restore(previous) end)
    :ok
  end

  test "with no seed nodes it gossips and finds whoever answers" do
    System.delete_env("ERLANG_SEED_NODES")

    assert [default: [strategy: Cluster.Strategy.Gossip]] = PluginNode.cluster_topologies()
  end

  test "with seed nodes it joins exactly those" do
    System.put_env("ERLANG_SEED_NODES", " a@host1 , b@host2 ")

    assert [default: [strategy: Cluster.Strategy.Epmd, config: [hosts: hosts]]] =
             PluginNode.cluster_topologies()

    assert hosts == [:a@host1, :b@host2]
  end

  test "a list of nothing but separators is no list at all" do
    System.put_env("ERLANG_SEED_NODES", " , ")

    assert [default: [strategy: Cluster.Strategy.Gossip]] = PluginNode.cluster_topologies()
  end

  defp restore(nil), do: System.delete_env("ERLANG_SEED_NODES")
  defp restore(value), do: System.put_env("ERLANG_SEED_NODES", value)
end
