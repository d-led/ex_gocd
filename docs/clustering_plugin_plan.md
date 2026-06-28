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
