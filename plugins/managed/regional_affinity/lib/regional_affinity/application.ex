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
      {Phoenix.PubSub, name: ExGoCD.PubSub},
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
    links = [{"Scheduling Decisions", "/admin/plugins"}]
    module = RegionalAffinity.AgentSelector
    slot = :agent_selector

    # Find ex_gocd nodes
    ex_gocd_nodes = Node.list() |> Enum.filter(&(to_string(&1) =~ ~r/ex_gocd/))

    if ex_gocd_nodes == [] do
      IO.warn("[regional_affinity] No ex_gocd nodes found, retrying...")
    else
      target = hd(ex_gocd_nodes)

      # Use :erpc.call for reliable cross-node invocation
      case :erpc.call(target, ExGoCD.Plugin.Registry, :register, [slot, module, secret]) do
        :ok ->
          IO.puts("[regional_affinity] Registered #{inspect(module)} as #{slot} on #{target}")
          # Also send UI links via the public API
          :erpc.call(target, ExGoCD.Plugin.Registry, :accept_ui_links, [slot, secret, links])

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
