defmodule SimpleOrgChart.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    topologies = [default: [strategy: Cluster.Strategy.Gossip]]

    children = [
      {Cluster.Supervisor, [topologies, [name: SimpleOrgChart.ClusterSupervisor]]}
    ]

    Task.start(fn ->
      Process.sleep(3_000)
      register_with_ex_gocd()

      Stream.interval(15_000)
      |> Stream.each(fn _ -> register_with_ex_gocd() end)
      |> Stream.run()
    end)

    opts = [strategy: :one_for_one, name: SimpleOrgChart.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp register_with_ex_gocd do
    secret = System.get_env("PLUGIN_SECRET") || ""
    ex_gocd = Node.list() |> Enum.find(&(to_string(&1) =~ ~r/ex_gocd/))

    if ex_gocd do
      GenServer.call(
        {ExGoCD.Plugin.Registry, ex_gocd},
        {:register, :org_hierarchy, SimpleOrgChart, secret, []}
      )

      IO.puts("[simple_org_chart] Registered as org_hierarchy on #{ex_gocd}")
    end
  end
end
