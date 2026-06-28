# Clustering & Plugin Architecture Plan

*Created 2026-06-28.*

## Architecture

```
┌─────────────────────────────────────────────────┐
│               OTP Cluster (libcluster)           │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ ex_gocd  │  │ ex_gocd  │  │ plugin-foo   │  │
│  │ :4000    │  │ :5000    │  │ (OTP app)    │  │
│  │ Phoenix  │  │ Phoenix  │  │              │  │
│  └──────────┘  └──────────┘  └──────────────┘  │
│       │              │              │            │
│  ┌────┴──────────────┴──────────────┴────┐      │
│  │         Horde (Registry + Supervisor)  │      │
│  │  Singleton processes:                  │      │
│  │  - Scheduler, ElasticAgentScheduler    │      │
│  │  - SnapshotCollector, Materials.Poller │      │
│  │  - ConsoleActivityMonitor, DiskSpace   │      │
│  └────────────────────────────────────────┘      │
└─────────────────────────────────────────────────┘
```

## Dependencies

- `{:libcluster, "~> 3.4"}` — automatic node discovery
- `{:horde, "~> 0.10"}` — distributed process registry + dynamic supervisor

## libcluster Topology

- Local dev: `Cluster.Strategy.Gossip` (multicast loopback discovery)
- Docker/prod: `Cluster.Strategy.Epmd` with `ERLANG_SEED_NODES`

## Horde Configuration

- `ExGoCD.HordeRegistry` — `Horde.Registry`, keys: unique, members: auto
- `ExGoCD.HordeSupervisor` — `Horde.DynamicSupervisor`, uniform distribution

## Singleton Pattern

```elixir
case GenServer.start_link(__MODULE__, opts,
  name: {:via, Horde.Registry, {ExGoCD.HordeRegistry, __MODULE__}}) do
  {:ok, pid} -> {:ok, pid}
  {:error, {:already_started, pid}} -> {:ok, pid}
end
```

## ClusterInfoServer

Polls `Node.list()` and `Horde.Registry.lookup/2` every 3s. Broadcasts via PubSub.

## Clustering Admin UI

New "Clustering" tab: node list, singleton locations (ball icon on owner), plugin discovery.

## Plugin Behaviour

```elixir
defmodule ExGoCD.Plugin do
  @callback name() :: String.t()
  @callback version() :: String.t()
  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback services() :: [atom()]
end
```

## process-compose

```yaml
server-4000: PORT=4000, name=ex_gocd@127.0.0.1
server-5000: PORT=5000, name=ex_gocd2@127.0.0.1
```

## Singleton GenServers to Convert

Scheduler, ElasticAgentScheduler, SnapshotCollector, Materials.Poller,
ConsoleActivityMonitor, MaintenanceMode, Backup, DiskSpace, AgentRegistry, TriggerMonitor

## Cypress

Mock mode unchanged. Both :4001 (mock) and multi-node tests pass.

## OpenTelemetry for Clustered Tracing

We already have: `opentelemetry`, `opentelemetry_exporter`, `opentelemetry_phoenix`, `opentelemetry_ecto`.

For distributed tracing across cluster nodes, add:
- **`opentelemetry_process_propagator`** (1M+ downloads) — propagates trace context across GenServer.call/cast boundaries between cluster nodes. Without it, traces break at node boundaries.
- **`opentelemetry_bandit`** (355K downloads) — traces incoming HTTP requests at the Bandit adapter level.
- **`o11y`** (226K downloads) — opinionated OTEL utilities, annotation helpers.

## Plugin Architecture

### Plugin Behaviour

```elixir
defmodule ExGoCD.Plugin do
  @callback name() :: String.t()
  @callback version() :: String.t()
  @callback services() :: %{atom() => module()}
  @callback start(Keyword.t()) :: {:ok, pid()} | {:error, term()}
end
```

### Plugin Slots

One plugin application may implement multiple plugin slots:

| Slot | Behaviour | Description |
|------|-----------|-------------|
| `:auth_provider` | `ExGoCD.Plugin.AuthProvider` | Authenticate users (LDAP, OAuth, GitHub) |
| `:agent_selector` | `ExGoCD.Plugin.AgentSelector` | Filter/reduce agent candidates after scheduler selection |
| `:pipeline_grouper` | `ExGoCD.Plugin.PipelineGrouper` | Custom pipeline grouping logic |
| `:org_hierarchy` | `ExGoCD.Plugin.OrgHierarchy` | Isolate pipeline groups per organizational node |
| `:notification_sink` | `ExGoCD.Plugin.NotificationSink` | Custom notification delivery (Slack, Teams, webhook) |

### Extension Points (minimal, well-defined interfaces)

```elixir
defmodule ExGoCD.Plugin.AgentSelector do
  @callback select([Agent.t()], Job.t()) :: [Agent.t()]
end

defmodule ExGoCD.Plugin.AuthProvider do
  @callback authenticate(map()) :: {:ok, User.t()} | {:error, term()}
end

defmodule ExGoCD.Plugin.PipelineGrouper do
  @callback group([Pipeline.t()]) :: %{String.t() => [Pipeline.t()]}
end
```

### Directory Layout

```
plugins/managed/{plugin_name}/
  mix.exs
  lib/{plugin_name}/application.ex
  lib/{plugin_name}/... .ex
```

Each plugin is a full OTP application that joins the cluster via libcluster.

## Plugin Ideas

1. **Auth Plugin** — replace stub auth with real LDAP/OAuth via Ueberauth
2. **Agent Candidate Selector** — post-scheduler selection filter (e.g., corporate policy)
3. **Pipeline Grouping** — custom grouping by team/department
4. **Org Hierarchy** — isolate pipeline groups per org chart node

## Milestone 1: 2-node cluster (DONE ✅)

- libcluster + Horde infrastructure committed
- process-compose.cluster.yaml with :4000 and :5000
- ClusterInfoServer polling singleton locations

## Milestone 2: Clustering Admin UI (TODO)

- Admin "Clustering" tab showing node list + singleton locations
- Ball icon on singleton owner node (like ssr-robust-live-svg)
