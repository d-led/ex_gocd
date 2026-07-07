# ex_gocd — Unified Feature Parity Plan

> Single source of truth. Supersedes all previous plan/roadmap/status documents.
> Last audited: 2026-07-08. 949 tests. 67 controllers. 21 LiveView pages. 20 GenServers. 42 migrations.
> **2026-07-08 audit:** DB-backed test report storage (JUnit/NUnit/XUnit), `test_reports`/`test_suites`/`test_cases` tables. Tests tab still uses legacy iframe — LiveView-native rewrite deferred.

---

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
| Testing       | ExUnit (900+ tests) + Cypress E2E (19 specs) + Go tests            |

### Cluster Topology

```
┌──────────────────────────────────────────────────────────┐
│  OTP Cluster (libcluster, gossip strategy)               │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────────┐  │
│  │ ex_gocd  │  │ ex_gocd2 │  │ sample_scheduling_plugin │  │
│  │ :4000    │  │ :4050    │  │ :4100 (AgentSelector) │  │
│  └──────────┘  └──────────┘  └───────────────────────┘  │
│       │              │              │                    │
│  ┌──────────┐  ┌─────────────────────────────────┐      │
│  │corp_policy│ │ simple_org_chart (:4101)        │      │
│  │:4102      │ │ enterprise_hierarchy (:4110)    │      │
│  └──────────┘  └─────────────────────────────────┘      │
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

| Slot                 | Behaviour                     | Implementations                                                              |
| -------------------- | ----------------------------- | ---------------------------------------------------------------------------- |
| `:agent_selector`    | `ExGoCD.Plugin.AgentSelector` | SampleSchedulingPlugin (region-aware), CorpPolicy (least-utilized)           |
| `:pipeline_grouper`  | Pipeline group assignment     | — (empty; DashboardLive falls back to static grouping)                       |
| `:org_hierarchy`     | Organization structure        | SimpleOrgChart, EnterpriseHierarchy (config-driven, YAML + JSON API, :4110)  |
| `:auth_provider`     | External authentication       | — (empty)                                                                    |
| `:notification_sink` | Build notifications           | — (empty; not yet wired)                                                     |

11 distributed singletons via Horde.DynamicSupervisor, OTEL process propagator,
`:erpc` plugin communication. Each plugin can expose its own LiveView UI.

### Architecture Differences vs GoCD

| Aspect               | GoCD (Java)                  | ex_gocd (Elixir)                                                    |
| -------------------- | ---------------------------- | ------------------------------------------------------------------- |
| **Runtime**          | JVM + Spring                 | BEAM (Erlang VM)                                                    |
| **Distribution**     | Single server + agents       | OTP cluster (libcluster gossip)                                     |
| **Plugin system**    | OSGi / GoCD plugin API       | Standalone OTP apps, self-registering                               |
| **Plugin comm**      | Java interfaces, in-process  | `:erpc` across cluster nodes                                        |
| **Plugin UI**        | Embedded in GoCD UI          | Independent Phoenix LiveViews on own ports                          |
| **Frontend**         | Angular/React SPA            | Phoenix LiveView (SSR over WebSocket)                               |
| **Observability**    | External analytics plugin    | Built-in OpenTelemetry + VSM tracing                                |
| **Agent**            | Java agent JAR (~50MB)       | Go binary (~10MB)                                                   |
| **Configuration**    | XML + CruiseConfig           | Ecto schemas + PostgreSQL                                           |
| **Database**         | H2 or PostgreSQL             | PostgreSQL only                                                     |
| **Secrets**          | GoCD cipher (AES)            | `ExGoCD.Cipher` (AES, same approach)                                |
| **Build dirs**       | `pipelines/{name}/` (shared) | `ex_gocd_jobs/{pipeline}/{counter}/...` (unique per job, circular)  |

---

## Current State

ex_gocd has achieved ~95% parity with GoCD. The remaining ~11 gaps are in 4 categories.

### Implemented (verified by source audit)

| Feature | API | LiveView | GenServer/Services |
|---------|-----|----------|-------------------|
| Pipeline scheduling | ✅ pause/unpause/unlock/schedule/status/comment | ✅ Dashboard + Activity + Config + Wizard | ✅ scheduler.ex |
| Stages & Jobs | ✅ show/history/cancel/rerun-failed | ✅ StageDetails + JobDetails + Gantt | ✅ stage_status.ex |
| Agents | ✅ CRUD + bulk + enable/disable | ✅ AgentsLive + AgentJobHistory + AgentJobRunDetail | ✅ agent_registry.ex |
| VSM | ✅ pipeline + material VSM routes | ✅ ValueStreamMapLive (all 5 phases) | ✅ vsm_tracer.ex |
| Analytics | ✅ | ✅ AnalyticsLive (all 5 dashboard types) | ✅ snapshot_collector.ex |
| Compare & Config Diff | ✅ | ✅ CompareLive + ConfigDiffLive | — |
| Config XML | ✅ export/import | ✅ AdminLive config XML tab | ✅ config_xml.ex + config_snapshot.ex |
| Config Repos (PaC) | ✅ CRUD + refresh | ✅ AdminLive config repos tab | ✅ config_repos/poller.ex |
| Config Versioning | — | ✅ AdminLive config XML history | ✅ config_version.ex |
| Templates | ✅ CRUD | ✅ AdminLive | ✅ pipelines/template.ex |
| Environments | ✅ CRUD | ✅ AdminLive | ✅ environments.ex |
| Users | ✅ CRUD | ✅ AdminLive | ✅ accounts/user.ex |
| Roles | ✅ CRUD | ✅ AdminLive | ✅ accounts/role.ex |
| PAT / Access Tokens | ✅ CRUD + revoke | ✅ AdminLive | ✅ accounts/personal_access_token.ex |
| Pipeline Group Permissions | ✅ CRUD | ✅ AdminLive | ✅ accounts/pipeline_group_permission.ex |
| Auth Configs | ✅ CRUD | ✅ AdminLive | ✅ auth_configs.ex |
| Notification Filters | ✅ CRUD | ✅ AdminLive | ✅ notifications.ex |
| Artifact Stores | ✅ CRUD | ✅ AdminLive | ✅ artifact_stores.ex |
| Cluster Profiles | ✅ CRUD | ✅ AdminLive | ✅ cluster_profiles.ex |
| Elastic Agent Profiles | ✅ CRUD | ✅ AdminLive | ✅ elastic_agent_profiles.ex |
| Package Repositories | ✅ CRUD | ✅ AdminLive | ✅ package_repositories.ex |
| Secret Configs | ✅ CRUD | ✅ AdminLive | ✅ secret_configs.ex |
| Backup | ✅ create API | ✅ AdminLive | ✅ backup.ex |
| Maintenance Mode | ✅ enable/disable/info | ✅ AdminLive | ✅ maintenance_mode.ex |
| Server Health | ✅ messages endpoint | ✅ | — |
| Plugin Info | ✅ list endpoint | ✅ PluginLive | ✅ plugin_registry.ex |
| CCTray XML Feed | ✅ /go/cctray.xml | — | — |
| Pipeline Atom Feed | ✅ /api/feeds/pipelines.xml | — | — |
| Webhooks | ✅ GitHub/GitLab/git notify | — | ✅ materials/poller.ex |
| SCM | ✅ materials list | ✅ MaterialsLive | ✅ materials/poller.ex |
| Dashboard API | ✅ GET /api/dashboard | — | — |
| Version API | ✅ GET /api/version | — | — |
| Stats API | ✅ GET /api/stats | — | — |
| Console Streaming | ✅ append API | ✅ JobDetailsLive console tab | ✅ pub_sub.ex |
| Artifacts | ✅ upload/download/browse | ✅ JobDetailsLive artifacts tab | ✅ artifact_cleanup.ex |
| Test Reports | ✅ JUnit/NUnit/XUnit → DB | ✅ JobDetailsLive tests tab (iframe — see G2) | ✅ test_report.ex (parser+DB store) |
| Audit Log | — | ✅ AuditLogLive (search/filter/links) | ✅ audit_log.ex |
| Scheduling Admin | — | ✅ AdminSchedulingLive | ✅ scheduling_checker.ex |
| External CI Wizard | — | ✅ ExternalCIRepoWizardLive | ✅ config_repos/parser.ex |
| Clustering | — | ✅ AdminLive cluster tab | ✅ libcluster+Horde, 10 singletons |
| Plugins | — | ✅ PluginLive + managed plugins | ✅ 5 behaviours, Plugin.Registry |
| Elastic Agent Scheduler | — | ✅ AdminLive K8s tab | ✅ elastic_agent_scheduler.ex (~1100 lines) |
| Go Agent | ✅ WebSocket protocol | — | ✅ agent/ (Go binary, ~700 lines) |
| Pipeline Build Cache | — | — | ❌ not started |
|| Docker Elastic Agent | — | — | ❌ K8s-only |
|| Pipeline config API | ✅ CRUD | ✅ AdminLive | FIXED: field name mismatch |

---

## Remaining Gaps

### 🟡 Category A: Missing API Endpoints (6)

| # | Gap | GoCD Path | Effort | Status |
|---|-----|-----------|--------|--------|
| A1 | **Encryption API** | `POST /go/api/admin/encrypt` | S | ✅ |
| A2 | **Agent Health Monitoring** | `GET /health/v1/isConnectedToServer` | M | ❌ |
| A3 | **Agent kill running tasks** | `POST /go/api/agents/:uuid/kill_running_tasks` | S | ✅ |
| A4 | **Pipeline Groups Admin API** | CRUD `/go/api/admin/pipeline_groups` | M | ❌ |
| A5 | **Backup Config API** | `GET/POST/DELETE /go/api/config/backup` | S | ❌ |
| A6 | **Backup Status Tracking** | `GET /go/api/backups/:backup_id` | S | ❌ |

### 🟡 Category B: Partial Features (4)

| # | Gap | Effort | Status | Notes |
|---|-----|--------|--------|-------|
| B1 | **Material VSM link in UI** | S | ✅ | Already wired in materials + pipeline activity |
| B2 | **Missing webhook endpoints** | S | ✅ | bitbucket-server/cloud, hg, other-scm added |
| B3 | **Feed XML incomplete** | S | ✅ | stage, job, material, scheduled-jobs feeds added |
| B4 | **Agent UI search/filter/sort** | M | ❌ | Search box exists, not functional |

### 🟡 Category C: SCM & Package Ecosystem (2)

| # | Gap | Effort | Status |
|---|-----|--------|--------|
| C1 | **Packages CRUD API** | M | ✅ |
| C2 | **Pluggable SCM full CRUD** | S | ⚠️ | Materials are pipeline-managed, not independent |

### 🟡 Category D: Planned but Not Started (2)

| # | Gap | Effort | Status |
|---|-----|--------|--------|
| D1 | **Artifact Caching Phase 1 (Zip cache)** | M | ❌ |
| D2 | **Docker Elastic Agent Path** | L | ❌ |

---

## Implementation Phases

### Phase 1: Quick Wins (S effort, this session) ✅
1. ✅ A1: Encryption API — controller + JSON view using existing crypto.ex
2. ✅ A3: Agent kill running tasks — action on agent_controller
3. ✅ B1: Material VSM link in UI — already wired, verified
4. ✅ B2: Missing webhook endpoints — added 4 handlers to webhook_controller
5. ✅ B3: Remaining feed XML — added 4 feed types to feeds_controller

### 🟡 Category E: UI Missing Links & Screens (7)

| # | Gap | GoCD Behavior | Effort | Status |
|---|-----|---------------|--------|--------|
| E1 | **Dashboard: Changes link on cards** | Dropdown showing material revisions/build cause per instance | S | ❌ |
| E2 | **Dashboard: Stage overview popup** | Clicking stage pill shows popup with job details | M | ❌ |
| E3 | **Dashboard: Group edit gear icon** | Edit pipeline group link on group heading (admin only) | S | ❌ |
| E4 | **Dashboard: New Pipeline dropdown** | "Use Pipeline Wizard" / "Use Pipelines as Code" on group heading | S | ❌ |
| E5 | **Job console: env-var echo too granular** | GoCD folds system bits into fewer commands; we echo each var into its own foldable block | S | ❌ |
| E6 | **Nav menu wildness** | "Sharing with Agent" button appearing incorrectly; partial sidebar "A..." | S | ❌ |
| E7 | **Stage details: missing links** | Stage Overview links to job details, config diff, pipeline compare | S | ✅ |

### 🟡 Category F: RBAC & Policy Enforcement (2)

| # | Gap | GoCD Behavior | Effort | Status |
|---|-----|---------------|--------|--------|
| F1 | **Per-environment RBAC** | Role policies (`<allow action="view" type="environment">UAT</allow>`) control environment access | M | ❌ |
| F2 | **Policy enforcement via Bodyguard** | `EnvironmentPolicy` only checks admin/dev/viewer roles — needs bodyguard hex package for proper policy evaluation | M | ❌ |

### 🟡 Category G: Job Details Tabs — Tests, Artifacts & Custom Tabs (3)

| # | Gap | GoCD Behavior | Effort | Status |
|---|-----|---------------|--------|--------|
| G1 | **Tests tab: LiveView-native rendering** | GoCD generates `testoutput/index.html` via XSLT → iframes it. We now parse JUnit/NUnit/XUnit into DB on upload (`parse_and_store/2`), but the Tests tab still uses an iframe pointing to old `index.html`. Should render pure LiveView Heex from Ecto data (summary cards, progress bar, test case tables). | M | ⚠️ DB-backed, UI deferred |
| G2 | **Artifacts tab: HTML View link** | GoCD serves HTML artifacts inline. Our artifacts tab shows directory tree with Download links only — HTML files (.html/.htm) should have a "View" link that opens in a new tab (ArtifactsController already serves correct `text/html` Content-Type). | S | ✅ |
| G3 | **Custom tabs from job config** | GoCD renders `<tabs><tab name="Cov" path="reports/coverage/index.html"/></tabs>` as iframe tabs in job details. Our `jobs.tabs` DB column exists but is never consumed by the LiveView. Should render custom tab buttons, each linking to `/files/.../{path}` in new tab (no iframe). | S | ✅ |

### 🟡 Cross-Linking Audit (2026-07-08)

| Page | Link | Status |
|------|------|--------|
| Dashboard | Pipeline name → Activity | ✅ |
| Dashboard | Stage pills → Stage Details | ✅ |
| Dashboard | VSM link per instance | ✅ |
| Dashboard | Compare link | ✅ |
| Dashboard | History link | ✅ |
| Dashboard | Changes dropdown (material revisions) | ❌ (E1) |
| Dashboard | Stage overview popup | ❌ (E2) |
| Pipeline Activity | VSM per instance | ✅ |
| Pipeline Activity | Material revision → material VSM | ✅ |
| Pipeline Activity | Config diff (⚙) per instance | ✅ |
| Pipeline Activity | Stage name → Stage Details | ✅ |
| Pipeline Activity | Stage Duration tab | ✅ |
| Stage Details | Breadcrumb: pipeline → Activity | ✅ |
| Stage Details | Breadcrumb: counter → VSM | ✅ |
| Stage Details | Job name → Job Details | ✅ |
| Stage Details | Agent name → Agent History | ✅ |
| Stage Details | Config Diff link | ✅ |
| Stage Details | Pipeline Compare link | ✅ |
| Stage Details | Graphs → Stage Duration chart | ✅ |
| Stage Duration | Dot → Stage Details (clickable) | ✅ |
| Stage Duration | Human-readable axis (m/h/s) | ✅ |
| VSM | Pipeline node → search | ✅ |
| VSM | Material revision → material VSM | ✅ |
| VSM | Stage result → Stage Details | ✅ |
| Job Details | Console, Tests, Artifacts, Materials, Env tabs | ✅ |
| Job Details | Custom tabs from job config | ✅ |
| Job Details | HTML View link in artifacts | ✅ |
| Agents | Job name → Job Details | ✅ |
| Admin Scheduling | Job name → Job Details | ✅ |

### Remaining Gaps (10)

#### Already Done (this session, 2026-07-08)
1. ✅ XML import/export for `<artifacts>` (type=build|test) and `<tabs>`
2. ✅ YAML config repo parser: normalize artifacts + tabs
3. ✅ Scheduler: `uploadTestArtifact` for type=test
4. ✅ Stage duration chart: human-readable axis + clickable dots
5. ✅ E7: Stage details Config Diff + Compare links
6. ✅ DB-backed test reports (JUnit/NUnit/XUnit)
7. ✅ G2: Artifacts HTML View link
8. ✅ G3: Custom tabs from job config
9. ✅ Seeds: ex_gocd dogfood with test artifacts + tabs

#### Remaining
6. A5: Backup config API
7. A6: Backup status tracking
8. A4: Pipeline groups admin API
9. C2: Pluggable SCM full CRUD
10. C1: Packages CRUD API

### Phase 3: Features (M-L)
11. B4: Agent UI search/filter/sort
12. A2: Agent health monitoring
13. D1: Artifact caching Phase 1
14. E2: Stage overview popup
15. F1+F2: RBAC with Bodyguard for per-environment policies
16. **G1: Tests tab LiveView-native** — replace iframe with pure Heex rendering from Ecto

### Phase 4: Stretch (L-XL)
17. D2: Docker elastic agent path
18. E1, E3, E4: Dashboard missing links

### Phase 5: Polish (S)
19. E5: Console env-var echo fix
20. E6: Nav menu cleanup

---

## Deferred / Not Planned

- Template authorization API — simpler role model doesn't need plugin-role-based auth
- Extract-to-template API — UI already supports creating templates
- Config repos operations (preflight, trigger_update, status, definitions) — poller covers core
- Default job timeout server config — per-job timeout already in Job schema
- Package material plugin support — needs full package plugin ecosystem
- Agent approval/pending workflow — simpler auto-register model

---

## Quality Baseline

| Check | Status |
|-------|--------|
| `mix compile --warnings-as-errors` | ✅ |
| `mix format --check-formatted` | ✅ |
| `mix sobelow` | ✅ 0 findings |
| `mix credo --strict` | ✅ |
| `mix test` | ✅ 949 passed |
| `go vet ./...` | ✅ |
| `go test ./...` | ✅ |
| `golangci-lint run` | ✅ 0 issues |
| Cypress E2E | ✅ 16 specs, 111+ passed |

---

## Superseded Documents

The following docs have been removed (consolidated here):

- ~~`comprehensive_parity_plan.md`~~ — merged into this file
- ~~`gocd_api_coverage.md`~~ — outdated (all claimed ❌ items now verified as ✅)
- ~~`AGENTS_UI_STATUS.md`~~ — merged (agents UI is complete, search/filter tracked as B4)
- ~~`artifact_caching_plan.md`~~ — merged (tracked as D1)
- ~~`elastic-agent-reaper.md`~~ — merged (reaper is done, tracked in elastic agent scheduler)
- ~~`status.md`~~ — merged (module mapping now in `module_mapping.md`)
- ~~`architecture_and_parity.md`~~ — merged (architecture, topology, plugin system, quality baseline)

### Reference Docs (kept, not merged)

- `module_mapping.md` — Elixir ↔ GoCD Java source file mapping
- `gocd_console_log_format.md` — tagged console stream format analysis
- `gocd_testing_analysis.md` — GoCD Java test patterns reference
- `mock_mode.md` — UI development without database (`USE_MOCK_DATA=true`)
- `plugin_authoring.md` — how to write standalone OTP plugins (5 behaviour slots)
- `pubsub_and_realtime_views.md` — PubSub broadcast pattern for LiveView updates
- `sobelow-justifications.md` — security scanner false positive explanations
