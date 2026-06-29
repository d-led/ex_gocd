defmodule DbAuthProvider.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    topologies = [default: [strategy: Cluster.Strategy.Gossip]]

    children = [
      {Cluster.Supervisor, [topologies, [name: DbAuthProvider.ClusterSupervisor]]}
    ]

    Task.start(fn ->
      Process.sleep(3_000)
      register_with_ex_gocd()

      Stream.interval(15_000)
      |> Stream.each(fn _ -> register_with_ex_gocd() end)
      |> Stream.run()
    end)

    opts = [strategy: :one_for_one, name: DbAuthProvider.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp register_with_ex_gocd do
    secret = System.get_env("PLUGIN_SECRET") || ""
    ex_gocd = Node.list() |> Enum.find(&(to_string(&1) =~ ~r/ex_gocd/))

    if ex_gocd do
      :erpc.call(ex_gocd, ExGoCD.Plugin.Registry, :register, [
        :auth_provider,
        DbAuthProvider,
        secret
      ])

      :erpc.call(ex_gocd, ExGoCD.Plugin.Registry, :accept_ui_links, [
        :auth_provider,
        secret,
        [{"DB Auth", "/admin/security"}]
      ])

      IO.puts("[db_auth_provider] Registered as org_hierarchy on #{ex_gocd}")
    end
  end
end
