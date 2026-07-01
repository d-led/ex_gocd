# Authoring ex_gocd Plugins

Plugins are **standalone OTP applications** that self-register with the
ex_gocd cluster via `ExGoCD.Plugin.Registry`. They connect through libcluster
gossip and authenticate with a shared `PLUGIN_SECRET`.

## Quick Start

Copy `plugins/managed/sample_scheduling_plugin/` as a template. The directory
contains a complete Phoenix app with the agent selector behaviour wired in.

```bash
cp -r plugins/managed/sample_scheduling_plugin plugins/managed/my_plugin
cd plugins/managed/my_plugin
# Update mix.exs: change :app, :version, deps as needed
# Update config/config.exs: change OTP app name
# Implement your behaviour
```

## Available Slots

| Slot | Behaviour | Purpose |
|------|-----------|---------|
| `:agent_selector` | `ExGoCD.Plugin.AgentSelector` | Custom agent-work matching logic |
| `:pipeline_grouper` | Pipeline group assignment | Override dashboard grouping |
| `:org_hierarchy` | Organization structure | Feed org chart into PipelineGroupPolicy |
| `:auth_provider` | External authentication | LDAP, OAuth, GitHub login |
| `:notification_sink` | Build notifications | Slack, email, webhook dispatch |

## Agent Selector

Implement `ExGoCD.Plugin.AgentSelector` behaviour and register in `application.ex`:

```elixir
# In your plugin's application.ex start/2:
ExGoCD.Plugin.Registry.register(:agent_selector, MyPlugin.AgentSelector)
```

The behaviour requires one callback:

```elixir
defmodule MyPlugin.AgentSelector do
  @behaviour ExGoCD.Plugin.AgentSelector

  @impl true
  def select_agent(agents, _opts) do
    # Return agent UUID (string) or nil to fall through
    # agents is a list of %ExGoCD.Agents.Agent{} structs
    agent = Enum.min_by(agents, & &1.free_space, fn -> nil end)
    agent && agent.uuid
  end
end
```

The scheduler calls `select_agent/2` via `:erpc` for every agent-work
assignment. Return `nil` to use default matching.

## Cluster Setup

Plugins join the cluster via libcluster gossip. Configure in `config/runtime.exs`:

```elixir
config :libcluster,
  topologies: [
    default: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45_890,
        if_name: "0.0.0.0",
        multicast_if: "127.0.0.1",
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1
      ]
    ]
  ]
```

Run in `process-compose` or docker-compose alongside the main server:

```yaml
my_plugin:
  command: "elixir --name my_plugin@127.0.0.1 --cookie ${COOKIE} -S mix phx.server"
  working_dir: "plugins/managed/my_plugin"
  environment:
    - "PORT=4200"
    - "MIX_ENV=dev"
    - "PLUGIN_SECRET=ex-gocd-demo-secret"
```

## LiveView UI

Plugins expose their own LiveView UI on their own port:

```elixir
# In your plugin's router.ex:
scope "/", MyPluginWeb do
  pipe_through :browser
  live "/", DashboardLive, :index
end
```

Implement `ui_links/0` in your main module to register the link in the
Plugin Dashboard (`/admin/plugins`):

```elixir
def ui_links, do: [%{title: "My Plugin", path: "/", port: 4200}]
```

## Example Plugins

| Plugin | Directory | Slot | Description |
|--------|-----------|------|-------------|
| SampleSchedulingPlugin | `plugins/managed/sample_scheduling_plugin/` | `:agent_selector` | Region-aware agent selection with audit log |
| CorpPolicy | `plugins/managed/corp_policy/` | `:agent_selector` | Corporate policy (least-utilized selection) |
| SimpleOrgChart | `plugins/managed/simple_org_chart/` | `:org_hierarchy` | Simple org hierarchy for pipeline permissions |

Each includes a `scripts/quality-gate.sh` for standalone CI testing.
