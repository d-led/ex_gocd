# Comprehensive GoCD Feature Parity Plan

*Audited 2026-06-21. Cross-referenced with actual codebase state.*

---

## Part A: Current State — Audited ✅

### API Controllers: 19 controllers, 81 actions across 6 scopes

| # | Controller | Actions | Scopes |
|---|-----------|---------|--------|
| 1 | `API.AgentController` | register, index, show, update, delete, enable, disable | `/api`, `/go/api` |
| 2 | `API.AnalyticsController` | index, show | `/api` |
| 3 | `API.BuildConsoleController` | append | `/api`, `/go/api` |
| 4 | `API.DashboardController` | show | `/api`, `/go/api` |
| 5 | `API.JobController` | schedule, show, history | `/api`, `/go/api` |
| 6 | `API.PersonalAccessTokenController` | index, show, create, revoke | `/api/current_user`, `/go/api/current_user` |
| 7 | `API.PipelineInstanceController` | history, show | `/api`, `/go/api` |
| 8 | `API.PipelineOperationsController` | status, pause, unpause, unlock, schedule, approve_stage | `/api`, `/go/api`, `/` |
| 9 | `API.StageController` | show, history, cancel | `/api`, `/go/api` |
| 10 | `API.StatsController` | show | `/api`, `/go/api` |
| 11 | `API.TestController` | start_agents, start_http_agents | `/api` (test only) |
| 12 | `API.UserController` | index, show, create, update, delete | `/api`, `/go/api` |
| 13 | `API.VersionController` | show | `/api`, `/go/api` |
| 14 | `API.WebhookController` | git_notify, github_notify, gitlab_notify | `/api`, `/go/api` |
| 15 | `API.Admin.BackupController` | create | `/api/admin` |
| 16 | `API.Admin.EnvironmentController` | index, show, create, update, delete | `/api/admin` |
| 17 | `API.Admin.MaintenanceModeController` | show, enable, disable | `/api/admin` |
| 18 | `API.Admin.PipelineConfigController` | show, create, update, delete | `/api/admin` |
| 19 | `API.Admin.TemplateController` | index, show, create, update, delete | `/api/admin` |

### LiveView Pages: 15 modules

| Module | Feature |
|--------|---------|
| `DashboardLive` | Main pipeline dashboard with VSM links |
| `AgentsLive` | Agents listing & status |
| `AgentJobHistoryLive` | Job history for a single agent |
| `AgentJobRunDetailLive` | Detail view of a single agent job run |
| `JobDetailsLive` | Console, Tests, Artifacts, Materials tabs |
| `StageDetailsLive` | Stage details with breadcrumbs → VSM |
| `PipelineActivityLive` | Pipeline run history with VSM buttons |
| `PipelineConfigLive` | Pipeline configuration editor |
| `PipelineWizardLive` | Wizard for creating new pipelines |
| `CompareLive` | Compare two pipeline runs |
| `ValueStreamMapLive` | VSM: trigger info, FI/FO badges, breadcrumbs, responsive |
| `MaterialsLive` | Materials (SCM) management |
| `AdminLive` | Admin settings / config |
| `AnalyticsLive` | Built-in CI analytics dashboard |
| `ExternalCIRepoWizardLive` | External CI repo config wizard |

### Core Features Audit

| Feature | Status | Notes |
|---------|--------|-------|
| Scheduler connected? check | ✅ | Checks Phoenix Presence + DB agent state fallback |
| AuthHeaderPlug | ✅ | No auto-bootstrap; nil for unknown users; guest admin when no admin |
| Test report generation | ✅ | JUnit XML → HTML via Erlang xmerl |
| Artifact tree browser | ✅ | Recursive directory listing in JobDetailsLive |
| Console live streaming | ✅ | PubSub-based console subscription |
| MD5 checksums | ✅ | Agent sends checksums; server stores |
| Maintenance mode | ✅ | GenServer: enable/disable/info; blocks triggers |
| Stage cancel | ✅ | `cancel_stage/3` with transaction |
| Cycle detection | ✅ | DFS cycle detector on pipeline dependency graph |
| Dashboard API | ✅ | `GET /api/dashboard` |
| Analytics | ✅ | 6 functions: pipeline, agent, VSM trends |
| Backup API | ✅ | `POST /api/admin/backups` (async pg_dump) |
| Environment API | ✅ | Full CRUD |
| Template API | ✅ | Full CRUD |
| Pipeline config API | ✅ | CRUD (show/create/update/delete) |
| User API | ✅ | Full CRUD |
| VSM | ✅ | Trigger info, FI/FO, breadcrumbs, responsive, E2E tests |
| Job instance API | ✅ | GET show/history, POST schedule |
| Stage instance API | ✅ | GET show/history, POST cancel |
| Pipeline instance API | ✅ | GET history/show |
| Agent remoting | ✅ | ping/get_work/report_status |
| Artifacts upload/download | ✅ | `/files/`, `/remoting/files/` |
| SCM polling | ✅ | Git polling, modification storage |
| Webhooks | ✅ | GitHub, GitLab, git notify |
| Fetch artifact task | ✅ | Agent-side protocol support |
| Go agent | ✅ | HTTP remoting agent in `agent/` |

---

## Part B: Remaining Gaps — Prioritized

### 🟡 P1: Completeness Polish

| # | Gap | Effort | Notes |
|---|-----|--------|-------|
| B1 | Pipeline config admin: `index` action handler | S | Route auto-generated but no controller `index/2` |
| B2 | Job comment API: `POST /api/pipelines/:name/:counter/comment` | S | Add controller action |
| B3 | Stage run-failed-jobs / run-selected-jobs APIs | M | Need stage re-trigger logic |
| B4 | Config XML import/export | M | Serialize DB → cruise-config.xml |
| B5 | Disk space monitor / artifact auto-cleanup | M | GenServer polling + purge policies |
| B6 | Artifact MD5 verification on downstream fetch | S | Verify checksums when fetching artifacts |

### 🟢 P2: Enterprise Features

| # | Gap | Effort | Notes |
|---|-----|--------|-------|
| B7 | Full config repos engine (PaC) | XL | YAML parsing, git polling, merge engine |
| B8 | External auth (LDAP/OAuth/GitHub) | L | Ueberauth or :eldap |
| B9 | Pipeline group administration | M | Delegate admin per group |
| B10 | Email notifications | M | Swoosh + PubSub + filter schema |
| B11 | Roles & auth configs CRUD | M | Bodyguard extension |
| B12 | Elastic agent profiles | L | Schema + API |
| B13 | Cluster profiles | L | Schema + API |
| B14 | Package repositories | L | Schema + API |
| B15 | Secret configs | L | Schema + API |
| B16 | Plugin info API | S | Metadata endpoint |

### 🔵 P3: Analytics Expansion

| # | Gap | Notes |
|---|-----|-------|
| B17 | Agent state transitions tracking | Schema exists (`agent_transition`) |
| B18 | Agent utilization snapshots | Periodic GenServer needed |
| B19 | Pipeline workflow chains | Traversal logic needed |
| B20 | VSM trend across runs | Query exists; UI charts needed |
| B21 | Analytics UI with Chart.js | LiveView exists; chart integration pending |

### ⚪ P4: Low Priority / Not Started

| # | Gap |
|---|-----|
| B22 | Feeds XML (pipeline/stage/job RSS) |
| B23 | Mailserver config |
| B24 | Site URLs config |
| B25 | Job timeout config |
| B26 | Notification filters |
| B27 | SCMs API |
| B28 | Permissions API |
| B29 | Artifact stores API |
| B30 | Server health API |

---

## Part C: Priority Matrix

| Priority | Items | Effort | Impact |
|----------|-------|--------|--------|
| **P0** | — | — | ✅ DONE |
| **P1** | Pipeline config index, job comment, stage re-run, disk monitor, XML export, checksum verify | S-M | Completeness |
| **P2** | Config repos, external auth, notifications, roles, elastic agents | L-XL | Enterprise |
| **P3** | Analytics UI, agent utilization, workflow chains, chart integration | M | User delight |
| **P4** | Feeds, mailserver, health, etc. | S-L | Low priority |

---

## Part D: Build & Quality

- **Tests**: 472 ExUnit tests, Go agent tests pass, Cypress E2E suite
- **Quality gate**: `scripts/quality-gate.sh` — compile `--warnings-as-errors`, Credo, Sobelow
- **Compile**: clean with `--warnings-as-errors` on all 146 files
- **Go agent**: `go build`, `go vet`, `go test ./...` — all clean

---

## Part E: VSM — Fully Shipped ✅

See [vsm_parity_plan.md](vsm_parity_plan.md) for full details. All 5 phases complete:
- Phase 1: trigger_info, fan_in, fan_out in data layer
- Phase 2: enriched JSON API inline
- Phase 3: UI with FI/FO badges, trigger panel, clickable nodes
- Phase 4: breadcrumbs, dashboard/activity/stage VSM links
- Phase 5: mobile responsive, aria-labels, Cypress E2E

---

## Part F: Analytics — Parity with gocd-analytics-plugin 🔴

Reference implementation: `../gocd-analytics-plugin/`

GoCD Analytics provides 4 dashboard types. Our `/analytics/global` page needs parity:

### F.1 VSM Analytics
- Pipeline lead time distribution (histogram)
- Material to pipeline completion time
- Bottleneck detection across pipeline chains

### F.2 Pipeline Analytics  
- Pipeline run frequency over time
- Pass/fail ratio charts
- Build duration trends
- Stage/job duration breakdowns

### F.3 Agent Analytics
- Agent utilization over time
- Idle vs building ratio
- Per-agent work distribution charts

### F.4 Global Analytics
- Cross-pipeline overview metrics
- System-wide throughput
- Aggregate success rates

**Status**: `/analytics/global` renders basic stats. Charts and time-series missing.
**Priority**: P2. Depends on agent utilization snapshots and pipeline metric collection.

---

## Part G: Pipeline Fan-In / Fan-Out (Material Chaining) 🔴

GoCD supports upstream pipeline outputs as downstream pipeline materials:
- Pipeline A produces artifacts → Pipeline B consumes them as material
- Automatic trigger when upstream completes
- VSM shows cross-pipeline dependencies

### G.1 Do we have this?
- `PipelineMaterialRevision` schema exists for pipeline-type materials
- Fan-in resolver (`FanInResolver`) validates consistency
- NOT demonstrated in demo/seed pipelines

### G.2 Needed
- Seed demo pipelines showing fan-in/fan-out chain
- UI: pipeline material type in config editor
- VSM: cross-pipeline dependency edges
- Dashboard: show downstream pipelines triggered by material

**Priority**: P1. Core GoCD feature, needs demo.

---

## Part H: Config Repositories 🔴

### H.1 Design clarification
Config repos DO NOT require checkout to disk. They represent pipeline-as-code definitions stored in git. The server pulls YAML/JSON pipeline definitions and upserts them into the DB. There is no workspace checkout.

### H.2 Current state
- `ConfigRepo` schema: url, branch, material_type, source_type
- `ConfigRepos` context: CRUD, list
- Admin UI: `/admin/config_repos` — lists repos, sync button
- External CI wizard: `/admin/config_repos/new` — manual entry, no guided wizard

### H.3 Gaps
- **Wizard persistence**: when re-syncing, forgets previously configured details. Must remember on re-sync.
- **Dashboard visibility**: config repos with `source_type: "gocd_pipeline"` should show which pipelines they created on the dashboard (config_repo_id FK on pipelines)
- **Pipeline group/label from config repo**: auto-assign pipeline group based on config repo metadata
- **Error reporting**: if a config repo fails to parse, show error on admin page
- **Auto-polling**: periodic git pull of config repos (existing Poller infrastructure can be reused)

**Priority**: P1. Dogfooding blocked until wizard works with persistence.

---

## Part I: Console Log Viewer 🔴

GoCD console log features we need parity with:
- Toggle timestamps on/off in log view
- Clickable links to individual log lines (anchors)
- Collapsible log sections (fold/unfold ANSI regions)
- Live log following (auto-scroll to bottom)
- Log search/highlight within a job

**Status**: Basic console log display exists. None of the above implemented.
**Priority**: P2. High user impact for debugging.

---

## Part J: Quick Win Sprint (this week)

| # | Item | Effort |
|---|------|--------|
| J.1 | Pipeline config admin `index` action | S — route exists, 1 missing handler |
| J.2 | Artifact MD5 verify on downstream fetch | S — checksums already computed |
| J.3 | Job comment API | S — 1 new controller action |
| J.4 | Config repo wizard persistence | M — store previous config in session/params |
| J.5 | Fan-in/fan-out demo seeds | S — seed 2 chained pipelines |
| J.6 | Config repo → pipeline dashboard mapping | S — show config_repo_id on pipeline cards |

---

*Plan updated 2026-06-22. Next: execute Part J Sprint.*
