# Clustering & Plugin Architecture Plan

*Created 2026-06-28. Updated 2026-06-29.*

## Status: Milestones 1-5 Complete ✅

- ✅ libcluster + Horde infrastructure (Gossip/Epmd topology)
- ✅ ClusterInfoServer broadcasting singleton locations via PubSub
- ✅ Admin "Clustering" tab at /admin/clustering
- ✅ process-compose.cluster.yaml (2 nodes: :4000 + :5000)
- ✅ process-compose.yaml non-clustered with `--sname ex_gocd` (additive join)
- ✅ Plugin architecture — 5 behaviour modules + Plugin.Registry GenServer
- ✅ M3: All 10 singletons distributed via Horde. DistSingleton env-aware: atom in test.
- ✅ M4: `opentelemetry_process_propagator` for cross-node trace linking
- ✅ M5: Plugin.Registry + AgentSelector wired into Scheduler. 3 example plugins:
  RegionalAffinity (GenServer + audit log), CorpPolicy, SimpleOrgChart.
  PluginDemoLive at /admin/plugins with real-time decision table.
- ✅ P4 cleared: B23 mailserver config, B24 site URLs, B27 SCMs API
- 🟡 Milestone 6: Auth plugin (Ueberauth/LDAP) in plugins/managed/ (L)
- 🟡 P2 remaining: config repos (XL), compare dialog (M), gantt (M)

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

### Extension Points (well-defined interfaces with exact types)

#### 1. AgentSelector — narrow the candidate pool

Hooks into `ExGoCD.Scheduler.find_matching_job/2`. After the scheduler filters
agents by resource/environment match, the plugin gets a final veto/reorder pass.

```elixir
defmodule ExGoCD.Plugin.AgentSelector do
  @moduledoc """
  Post-match agent filter. Called after the scheduler has found candidate agents
  that satisfy resource/environment constraints. The plugin can narrow or reorder
  the list before one agent is picked.

  Return `{:ok, agents}` to use a filtered subset, or `{:reject, reason}` to
  veto the entire assignment (job stays queued).
  """

  @type agent :: ExGoCD.Agents.Agent.t()
  @type job_spec :: map()  # %{pipeline:, stage:, job:, resources:, environments:, ...}

  @callback select_candidates([agent()], job_spec(), keyword()) ::
              {:ok, [agent()]} | {:reject, String.t()}
end
```

**Integration point** — `lib/ex_gocd/scheduler.ex` line ~395 (`find_matching_job`):

```elixir
# Current code:
defp find_matching_job(agent, queue) do
  # ... resource/env matching ...
end

# With plugin (conceptual):
defp find_matching_job(agent, queue) do
  candidates = Enum.filter(queue, &resource_env_match?(&1, agent))
  case ExGoCD.Plugin.Registry.get(:agent_selector) do
    nil -> Enum.find(candidates, fn _ -> true end)
    mod -> case mod.select_candidates([agent], hd(candidates), []) do
      {:ok, [agent]} -> hd(candidates_with_job)
      {:reject, _} -> nil
    end
  end
end
```

**Example: RegionalAffinity** — prefer agents in the same region as the pipeline:

```elixir
defmodule Plugins.Managed.RegionalAffinity do
  @behaviour ExGoCD.Plugin.AgentSelector

  def select_candidates(agents, job_spec, _opts) do
    region = Map.get(job_spec, :region, "us-east-1")
    {same_region, others} = Enum.split_with(agents, &(&1.region == region))
    {:ok, same_region ++ others}
  end
end
```

**Example: CorporatePolicy** — never schedule GPU jobs on spot instances:

```elixir
defmodule Plugins.Managed.CorpPolicy do
  @behaviour ExGoCD.Plugin.AgentSelector

  def select_candidates(agents, job_spec, _opts) do
    needs_gpu? = "gpu" in (job_spec.resources || [])
    if needs_gpu? do
      filtered = Enum.reject(agents, &(&1.elastic_agent_id != nil))
      if filtered == [], do: {:reject, "No non-spot GPU agents available"}, else: {:ok, filtered}
    else
      {:ok, agents}
    end
  end
end
```

#### 2. PipelineGrouper — dynamic pipeline grouping

Currently pipelines carry a static `pipeline_group` string. A grouper plugin replaces
that with dynamic computation — grouping by team, department, project, or external
data source. Used by the dashboard, pipeline list, and auth policies.

```elixir
defmodule ExGoCD.Plugin.PipelineGrouper do
  @moduledoc """
  Computes pipeline groups dynamically. Called whenever the pipeline list is
  fetched (dashboard, admin, API). May consult external data (LDAP, GitHub teams,
  config repo metadata).
  """

  @type pipeline :: ExGoCD.Pipelines.Pipeline.t()
  @type group_name :: String.t()

  @callback compute_groups([pipeline()], keyword()) :: %{group_name() => [pipeline()]}

  @callback group_for_pipeline(pipeline(), keyword()) :: group_name()
end
```

**Integration point** — `lib/ex_gocd/pipelines.ex` (or wherever `list_pipelines/0` is used):

```elixir
# Current code groups by pipeline.pipeline_group field.
# With plugin:
def list_pipelines_grouped do
  pipelines = Repo.all(Pipeline)
  case ExGoCD.Plugin.Registry.get(:pipeline_grouper) do
    nil -> Enum.group_by(pipelines, &(&1.pipeline_group || "default"))
    mod -> mod.compute_groups(pipelines, [])
  end
end
```

**Example: TeamFromGitHub** — group pipelines by GitHub CODEOWNERS:

```elixir
defmodule Plugins.Managed.GitHubTeamGrouper do
  @behaviour ExGoCD.Plugin.PipelineGrouper

  def compute_groups(pipelines, _opts) do
    pipelines
    |> Enum.group_by(fn p ->
      case Repo.one(from pg in "pipeline_git_materials",
                     where: pg.pipeline_id == ^p.id, limit: 1) do
        nil -> "ungrouped"
        mat -> fetch_codeowners_team(mat.repository_url) || "ungrouped"
      end
    end)
  end

  def group_for_pipeline(pipeline, _opts), do: pipeline.pipeline_group || "default"
end
```

#### 3. OrgHierarchy — isolate pipelines by org chart node

An org chart is a tree of departments/teams. Each node can own pipeline groups.
Auth policies consult the org hierarchy to determine access: "VP of Engineering
can operate all pipelines under the Engineering org node and its children."

```elixir
defmodule ExGoCD.Plugin.OrgHierarchy do
  @moduledoc """
  Provides an organizational tree. Each node has pipeline groups, and access
  propagates down the tree. Used by PipelineGroupPolicy to authorize users.

  The plugin is consulted at auth decision time — it maps `User → OrgNode → PipelineGroups`.
  """

  @type org_node :: %{
    id: String.t(),
    name: String.t(),
    pipeline_groups: [String.t()],
    children: [org_node()]
  }

  @callback org_tree(keyword()) :: org_node()

  @callback pipeline_groups_for_user(User.t(), keyword()) :: [String.t()]

  @callback user_org_node(User.t(), keyword()) :: {:ok, org_node()} | nil
end
```

**Integration point** — `lib/ex_gocd/policies/pipeline_group_policy.ex`:

```elixir
# Current: checks static pipeline_group_permissions table.
# With plugin:
def authorize(action, user, resource) do
  case ExGoCD.Plugin.Registry.get(:org_hierarchy) do
    nil -> static_authorize(action, user, resource)  # current logic
    mod ->
      groups = mod.pipeline_groups_for_user(user, [])
      if resource.pipeline_group in groups, do: :ok, else: {:error, :forbidden}
  end
end
```

**Example: SimpleOrgChart** — hardcoded org with three departments:

```elixir
defmodule Plugins.Managed.SimpleOrgChart do
  @behaviour ExGoCD.Plugin.OrgHierarchy

  @tree %{
    id: "root", name: "Acme Corp", pipeline_groups: [], children: [
      %{id: "eng", name: "Engineering", pipeline_groups: ["eng-frontend", "eng-backend"], children: []},
      %{id: "data", name: "Data Science", pipeline_groups: ["ml-pipelines", "etl"], children: []},
      %{id: "ops", name: "Platform Ops", pipeline_groups: ["infra", "deploy"], children: []}
    ]
  }

  def org_tree(_opts), do: @tree

  def pipeline_groups_for_user(user, _opts) do
    case user.department do
      "engineering" -> ["eng-frontend", "eng-backend"]
      "data" -> ["ml-pipelines", "etl"]
      "ops" -> ["infra", "deploy"]
      _ -> []
    end
  end

  def user_org_node(user, _opts) do
    find_node(@tree, user.department)
  end

  defp find_node(nil, _), do: nil
  defp find_node(%{children: children} = node, dept) do
    if node.id == dept, do: {:ok, node},
    else: Enum.find_value(children, &find_node(&1, dept))
  end
end
```

#### 4. AuthProvider — pluggable authentication

```elixir
defmodule ExGoCD.Plugin.AuthProvider do
  @callback authenticate(map()) :: {:ok, ExGoCD.Accounts.User.t()} | {:error, term()}
  @callback auth_plug_opts() :: keyword()  # for Phoenix router pipeline
end
```

#### 5. NotificationSink — custom delivery channels

```elixir
defmodule ExGoCD.Plugin.NotificationSink do
  @callback deliver(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  # deliver(event_type, message, opts) — event_type: "stage_failed", "pipeline_paused", etc.
end
```

### Plugin Registry

A single GenServer that loads plugin modules from config and answers
`ExGoCD.Plugin.Registry.get(:agent_selector)` → `module() | nil`.

```elixir
# config/dev.exs
config :ex_gocd, :plugins, [
  agent_selector: Plugins.Managed.RegionalAffinity,
  pipeline_grouper: Plugins.Managed.GitHubTeamGrouper,
  org_hierarchy: Plugins.Managed.SimpleOrgChart
]
```

### Directory Layout

```
plugins/managed/{plugin_name}/
  mix.exs
  lib/{plugin_name}/application.ex
  lib/{plugin_name}/... .ex
```

Each plugin is a full OTP application that joins the cluster via libcluster.

## Plugin Ideas — Detailed

| # | Plugin | Slot | Use Case | Effort |
|---|--------|------|----------|--------|
| 1 | **LDAP/OAuth Auth** | `:auth_provider` | Replace stub auth with real login | L |
| 2 | **Regional Affinity** | `:agent_selector` | Prefer agents in same region as pipeline | S |
| 3 | **Corporate Policy** | `:agent_selector` | Exclude spot/preemptible agents for GPU jobs | S |
| 4 | **GitHub Team Grouper** | `:pipeline_grouper` | Group pipelines by CODEOWNERS team | M |
| 5 | **Org Chart** | `:org_hierarchy` | Isolate pipeline groups by department | M |
| 6 | **Slack Notifier** | `:notification_sink` | Post stage failures to Slack | S |


## Milestone 1: 2-node cluster (DONE ✅)

- libcluster + Horde infrastructure committed
- process-compose.cluster.yaml with :4000 and :5000
- ClusterInfoServer polling singleton locations

## Milestone 2: Clustering Admin UI (DONE ✅)

- Admin "Clustering" tab showing node list + singleton locations
- Ball icon on singleton owner node (like ssr-robust-live-svg)
- PubSub subscription for live cluster updates

## Milestone 3: Distributed Singletons (DONE ✅)

- `DistSingleton` module with env-aware registration (atom in test, Horde in dev/prod)
- All 10 singletons converted: Scheduler, AgentRegistry, Poller, TimerScheduler,
  ConsoleActivityMonitor, TriggerMonitor, DiskSpace, ElasticAgentScheduler,
  MaintenanceMode, SnapshotCollector, Backup
- No `:timer.sleep` — supervisor sequential startup guarantees Horde readiness
- 852 tests, 0 skipped, 8.6s

## Milestone 4: OTEL Cross-Node Tracing (DONE ✅)

- Added `{:opentelemetry_process_propagator, "~> 0.3"}` to deps
- Added `ExGoCD.Otel.fetch_parent_ctx/1` helper
- `opentelemetry_bandit` deferred — dep conflict with `opentelemetry_phoenix` on
  `semantic_conventions` version (0.2 vs 1.27). Wait for phoenix otel 2.0 compat.
- Cross-node trace propagation works via OTP 25+ built-in process dictionary.

## Milestone 5: Plugin Registry + AgentSelector (DONE ✅)

- `ExGoCD.Plugin.Registry` GenServer — reads config, validates behaviours, 5 slots
- `AgentSelector` wired into `Scheduler.find_matching_job/2` via `plugin_approves?/3`
- 3 example plugins in `lib/ex_gocd/plugin/managed/`:
  - `RegionalAffinity` — GenServer + AgentSelector, logs last 200 decisions
  - `CorpPolicy` — GPU→spot rejection, deploy→production requirement
  - `SimpleOrgChart` — org tree → pipeline group access
- `PluginDemoLive` at `/admin/plugins` — real-time decision table, 2s refresh
- Always-on: `RegionalAffinity` loaded by default via `config.exs`
- 859 tests, 0 skipped

## Milestone 6: Auth Plugin (L effort) — not started

Replace stub auth with real LDAP/OAuth. Includes the `OrgHierarchy` slot for
department-scoped access.

- [ ] Add `{:ueberauth, "~> 0.10"}` and an LDAP strategy to deps
- [ ] Implement `ExGoCD.Plugin.AuthProvider` behaviour
- [ ] Wire into `AuthPlug` — if plugin registered, delegate authenticate to it
- [ ] Wire `SimpleOrgChart` into `PipelineGroupPolicy` for department-scoped access
- [ ] Tests: LDAP user logs in → sees only their department's pipelines
