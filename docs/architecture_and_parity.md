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

## GoCD Feature Parity

### Environment Variables — ✅ Complete

| Source                                                          | ex_gocd                                                       |
| --------------------------------------------------------------- | ------------------------------------------------------------- |
| Pipeline/Stage/Job config vars (plain)                          | ✅ `environment_variables` map                                |
| Pipeline/Stage/Job secure vars                                  | ✅ `secure_variables` map (AES encrypted via `ExGoCD.Cipher`) |
| Environment-level vars                                          | ✅ `ExGoCD.Environments.get_pipeline_environment/1`           |
| Trigger overrides (`variables`, `secure_variables` in API body) | ✅ scope-validated via `validate_trigger_variables/2`         |
| `GO_PIPELINE_NAME`, `GO_PIPELINE_COUNTER`, `GO_PIPELINE_LABEL`  | ✅                                                            |
| `GO_STAGE_NAME`, `GO_STAGE_COUNTER`                             | ✅                                                            |
| `GO_JOB_NAME`, `GO_SERVER_URL`, `GO_TRIGGER_USER`               | ✅                                                            |
| `GO_PIPELINE_GROUP_NAME`, `GO_ENVIRONMENT_NAME`                 | ✅                                                            |
| `GO_AGENT_RESOURCES`                                            | ✅ injected at assignment time                                |
| `GO_REVISION`, `GO_FROM_REVISION`, `GO_TO_REVISION`             | ✅                                                            |
| `GO_MATERIAL_HAS_CHANGED`, `GO_MATERIAL_{TYPE}_URL`             | ✅                                                            |
| Console echo (`setting environment variable: NAME=value`)       | ✅ echo subcommand                                            |
| Secure redaction (`********` in console)                        | ✅                                                            |
| Storage for retry (on `AgentJobRun.environment_variables`)      | ✅ JSON column                                                |
| Environment tab in job details UI                               | ✅                                                            |

### Pipeline Scheduling — ✅ Complete

Resource/environment matching (case-insensitive). Agent UUID affinity.
Run-on-all-agents. Stage activation (first stage only, GoCD parity).
Pipeline pause/lock checkers. FIFO fairness. Manual stage gates.
Fan-in resolution. Pipeline comparison (VSM + compare view).

### REST API

`GET /api/pipelines/:name/history`, `GET /api/pipelines/:name/:counter`,
`GET/POST /api/stages/...`, `GET /api/jobs/...`,
`POST /api/pipelines/:name/schedule` (with env var + material overrides),
`POST /api/pipelines/:name/pause|unpause`, `GET/POST/PATCH/DELETE /api/users/...`,
`GET/POST/PUT/DELETE /api/admin/pipelines/:name`, `GET /api/dashboard`,
`GET /go/cctray.xml`. Templates and environments CRUD APIs are schema-only.

### Agent

WebSocket connection + auto-reconnect. Build command tree execution.
Console streaming (timestamped lines). Artifact upload (including folder).
Material checkout (git, svn). Environment variable export.
Fold markers (`##[fold]` / `##[endfold]`). OTEL trace propagation (W3C).
Elastic agent (self-terminating on idle). Docker agent (socket auto-detect).
MD5 checksums for artifacts.

Missing: Fetch artifact task, console activity monitor.

### Job Details

Console Log (with folds), Tests (JUnit XML → HTML), Artifacts (tree browser),
Materials, **Environment** (ex_gocd addition), Timestamps toggle, Line wrap,
Follow (auto-scroll), Filter, Raw output download, Working directory display.

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

## Quality Baseline (2026-06-30)

| Check                                   | Status                   |
| --------------------------------------- | ------------------------ |
| `mix compile --warnings-as-errors`      | ✅                       |
| `mix format --check-formatted`          | ✅                       |
| `mix sobelow`                           | ✅ 0 findings            |
| `mix credo --strict`                    | ✅                       |
| `mix test`                              | ✅ 873 passed            |
| `go vet ./...`                          | ✅                       |
| `go test ./...`                         | ✅                       |
| `golangci-lint run`                     | ✅ 0 issues              |
| ESLint + TypeScript + Prettier          | ✅                       |
| Cypress E2E                             | ✅ 116 specs, 114 passed |
| Link checker (6 entry points, 74 links) | ✅ 0 errors              |
