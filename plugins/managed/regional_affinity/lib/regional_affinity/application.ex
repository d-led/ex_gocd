defmodule RegionalAffinity.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = [
      default: [
        strategy: Cluster.Strategy.Gossip
      ]
    ]

    children = [
      {Cluster.Supervisor, [topologies, [name: RegionalAffinity.ClusterSupervisor]]},
      RegionalAffinityWeb.Telemetry,
      {Phoenix.PubSub, name: RegionalAffinity.PubSub},
      Supervisor.child_spec({Phoenix.PubSub, name: ExGoCD.PubSub}, id: :cross_node_pubsub),
      RegionalAffinity.SchedulingDecisions,
      RegionalAffinityWeb.Endpoint
    ]

    # Self-register with ex_gocd on startup (and periodically)
    Task.start(fn ->
      Process.sleep(3_000)
      register_with_ex_gocd()

      # Rebroadcast periodically in case ex_gocd restarted
      Stream.interval(15_000)
      |> Stream.each(fn _ -> register_with_ex_gocd() end)
      |> Stream.run()
    end)

    opts = [strategy: :one_for_one, name: RegionalAffinity.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp register_with_ex_gocd do
    secret = System.get_env("PLUGIN_SECRET") || ""
    port = System.get_env("PORT", "4100")
    links = [{"Scheduling Decisions", "http://localhost:#{port}"}]
    module = RegionalAffinity.AgentSelector
    slot = :agent_selector

    # Find ex_gocd nodes
    ex_gocd_nodes = Node.list() |> Enum.filter(&(to_string(&1) =~ ~r/ex_gocd/))

    if ex_gocd_nodes == [] do
      IO.warn("[regional_affinity] No ex_gocd nodes found, retrying...")
    else
      target = hd(ex_gocd_nodes)

      # Call from THIS node so Plugin.Registry can track our real node
      registry = {ExGoCD.Plugin.Registry, target}

      case GenServer.call(registry, {:register, slot, module, secret, links}) do
        :ok ->
          IO.puts("[regional_affinity] Registered #{inspect(module)} + UI on #{target}")

        other ->
          IO.warn("[regional_affinity] Registration failed: #{inspect(other)}")
      end
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    RegionalAffinityWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
