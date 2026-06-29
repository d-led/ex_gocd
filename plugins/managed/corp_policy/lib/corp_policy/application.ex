defmodule CorpPolicy.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    topologies = [default: [strategy: Cluster.Strategy.Gossip]]

    children = [
      {Cluster.Supervisor, [topologies, [name: CorpPolicy.ClusterSupervisor]]}
    ]

    Task.start(fn ->
      Process.sleep(3_000)
      register_with_ex_gocd()

      Process.sleep(15_000)
      register_with_ex_gocd()
      Process.sleep(15_000)
      register_with_ex_gocd()
    end)

    opts = [strategy: :one_for_one, name: CorpPolicy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp register_with_ex_gocd do
    secret = System.get_env("PLUGIN_SECRET") || ""
    ex_gocd = Node.list() |> Enum.find(&(to_string(&1) =~ ~r/ex_gocd/))

    if ex_gocd do
      GenServer.call(
        {ExGoCD.Plugin.Registry, ex_gocd},
        {:register, :agent_selector, CorpPolicy, secret, []}
      )

      IO.puts("[corp_policy] Registered as agent_selector on #{ex_gocd}")
    end
  end
end
