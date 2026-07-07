defmodule EnterpriseHierarchy.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    topologies = [default: [strategy: Cluster.Strategy.Gossip]]

    children = [
      {Cluster.Supervisor, [topologies, [name: EnterpriseHierarchy.ClusterSupervisor]]},
      {EnterpriseHierarchy, []}
    ]

    # Start HTTP API only in non-test environments
    children = if Mix.env() == :test, do: children, else: children ++ http_child()

    # Retry registration indefinitely (15s between attempts)
    Task.start(fn ->
      Process.sleep(5_000)
      register_loop()
    end)

    opts = [strategy: :one_for_one, name: EnterpriseHierarchy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp register_loop do
    case register_with_ex_gocd() do
      :ok -> :ok
      :error ->
        Process.sleep(15_000)
        register_loop()
    end
  end

  defp register_with_ex_gocd do
    secret = System.get_env("PLUGIN_SECRET") || ""
    ex_gocd = Node.list() |> Enum.find(&(to_string(&1) =~ ~r/ex_gocd/))

    if ex_gocd do
      try do
        GenServer.call(
          {ExGoCD.Plugin.Registry, ex_gocd},
          {:register, :org_hierarchy, EnterpriseHierarchy, secret, []},
          5_000
        )
        IO.puts("[enterprise_hierarchy] Registered as org_hierarchy on #{ex_gocd}")
        :ok
      rescue
        e ->
          IO.puts("[enterprise_hierarchy] Registration failed: #{Exception.message(e)}")
          :error
      end
    else
      :error
    end
  end

  defp api_port do
    case System.get_env("HIERARCHY_API_PORT") do
      nil -> 4110
      port -> String.to_integer(port)
    end
  end

  defp dispatch do
    [{:_, [{:_, Plug.Cowboy.Handler, {EnterpriseHierarchy.API, []}}]}]
  end

  defp http_child do
    [{Plug.Cowboy, scheme: :http, plug: EnterpriseHierarchy.API,
      options: [port: api_port(), dispatch: dispatch()]}]
  end
end
