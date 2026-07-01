# ex_gocd — Architecture & GoCD Parity

## Architecture

ex_gocd is an Elixir/Phoenix rewrite of Thoughtworks GoCD, designed as a
distributed OTP cluster with plugin extensibility and built-in observability.

### Stack

| Layer         | Technology                                                         |
| ------------- | ------------------------------------------------------------------ |
| Server        | Elixir + Phoenix LiveView + Ecto (PostgreSQL)                      |
| Agents        | Go (`agent/`) — lightweight, self-registering, WebSocket-connected |
| Plugins       | Standalone OTP applications, self-registering via libcluster       |
| Observability | OpenTelemetry (OTLP → Jaeger), built-in VSM tracing                |
| Frontend      | Phoenix LiveView (SSR) + Tailwind CSS + daisyUI                    |
| Testing       | ExUnit (873 tests) + Cypress E2E (116 specs) + Go tests            |

### Cluster Topology

```
┌──────────────────────────────────────────────────────────┐
│  OTP Cluster (libcluster, gossip strategy)               │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────────┐  │
│  │ ex_gocd  │  │ ex_gocd2 │  │ regional_affinity     │  │
│  │ :4000    │  │ :4050    │  │ :4100 (AgentSelector) │  │
│  └──────────┘  └──────────┘  └───────────────────────┘  │
│       │              │              │                    │
│  ┌──────────┐  ┌───────────────────────┐                │
│  │corp_policy│ │ simple_org_chart      │                │
│  │:4102      │ │ :4101 (OrgHierarchy)  │                │
│  └──────────┘  └───────────────────────┘                │
│                                                          │
│  Agents (Go, WebSocket):                                 │
│    ci-agent (elixir,postgres)                            │
│    docker-agent (docker)                                 │
│    elastic-docker-agent (elastic, self-terminating)      │
└──────────────────────────────────────────────────────────┘
```

### Plugin Architecture

Plugins are **standalone OTP applications** that self-register with the
cluster via `ExGoCD.Plugin.Registry`. They connect through libcluster
gossip and authenticate with a shared `PLUGIN_SECRET`.

Available plugin slots:

| Slot                 | Behaviour                     | Example                                                          |
| -------------------- | ----------------------------- | ---------------------------------------------------------------- |
| `:agent_selector`    | `ExGoCD.Plugin.AgentSelector` | `RegionalAffinity` (region-aware), `CorpPolicy` (least-utilized) |
| `:pipeline_grouper`  | Pipeline group assignment     | —                                                                |
| `:org_hierarchy`     | Organization structure        | `SimpleOrgChart`                                                 |
| `:auth_provider`     | External authentication       | —                                                                |
| `:notification_sink` | Build notifications           | —                                                                |

Each plugin can expose its own **LiveView UI** via `ui_links/0` — accessible
both from the main Plugin Dashboard (`/admin/plugins`) and directly on their
own ports (e.g. `:4100` for RegionalAffinity).

### Scheduling Plugin — Regional Affinity

Implements the `AgentSelector` behaviour. The scheduler calls the plugin via
`:erpc` for every agent-work assignment. The plugin applies regional affinity
(prefer same-region agents), logs decisions to a GenServer, and broadcasts
via PubSub to a real-time LiveView at `:4100`.

Every decision includes a human-readable reason:

```
"Regional affinity: ci-agent is in same region (us-east-1), idle, least-utilized"
```

### Built-in OpenTelemetry

ex_gocd instruments every pipeline trigger, scheduler assignment, job
execution, and agent status change with OpenTelemetry spans via the VSM
(Value Stream Map) tracer. Spans propagate across the Go agent via W3C trace
context headers in WebSocket build messages. No external plugin required.

---

## GoCD Feature Parity — Complete

All major GoCD features are implemented: environment variables, pipeline scheduling, REST API (20+ controllers, 83+ actions), Go agent (WebSocket, console streaming, artifacts, elastic), job details (console, tests, artifacts, materials), value stream map, analytics, embedded stats, enhanced compare, Gantt/timeline, external auth (oauth2-proxy + PAT), config repos engine (Git poller + YAML/JSON parser), clustering (libcluster + Horde), and plugin system (5 behaviour slots).

---

## Architecture Differences

| Aspect                   | GoCD (Java)                  | ex_gocd (Elixir)                                                           |
| ------------------------ | ---------------------------- | -------------------------------------------------------------------------- |
| **Runtime**              | JVM + Spring                 | BEAM (Erlang VM)                                                           |
| **Distribution**         | Single server + agents       | OTP cluster (libcluster gossip)                                            |
| **Plugin system**        | OSGi / GoCD plugin API       | Standalone OTP apps, self-registering                                      |
| **Plugin communication** | Java interfaces, in-process  | `:erpc` across cluster nodes                                               |
| **Plugin UI**            | Embedded in GoCD UI          | Independent Phoenix LiveViews on own ports                                 |
| **Frontend**             | Angular/React SPA            | Phoenix LiveView (SSR over WebSocket)                                      |
| **Observability**        | External analytics plugin    | Built-in OpenTelemetry + VSM tracing                                       |
| **Agent**                | Java agent JAR               | Go binary (single-file, ~10 MB)                                            |
| **Configuration**        | XML + CruiseConfig           | Ecto schemas + PostgreSQL                                                  |
| **Database**             | H2 or PostgreSQL             | PostgreSQL only                                                            |
| **Secrets**              | GoCD cipher (AES)            | `ExGoCD.Cipher` (AES, same approach)                                       |
| **Build dirs**           | `pipelines/{name}/` (shared) | `ex_gocd_jobs/{pipeline}/{counter}/...` (unique per job, circular cleanup) |

---

## Quality Baseline (2026-07-01)

| Check                                   | Status                   |
| --------------------------------------- | ------------------------ |
| `mix compile --warnings-as-errors`      | ✅                       |
| `mix format --check-formatted`          | ✅                       |
| `mix sobelow`                           | ✅ 0 findings            |
| `mix credo --strict`                    | ✅                       |
| `mix test`                              | ✅ 890 passed            |
| `go vet ./...`                          | ✅                       |
| `go test ./...`                         | ✅                       |
| `golangci-lint run`                     | ✅ 0 issues              |
| ESLint + TypeScript + Prettier          | ✅                       |
| Cypress E2E                             | ✅ 16 specs, 111+ passed |
| Link checker                            | ✅ 0 errors              |
