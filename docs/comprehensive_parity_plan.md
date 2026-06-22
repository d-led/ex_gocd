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

| # | Item | Effort | Status |
|---|------|--------|--------|
| J.1 | Pipeline config admin `index` action | S | ✅ done |
| J.2 | Artifact MD5 verify on downstream fetch | S | 🔴 |
| J.3 | Job comment API | S | 🔴 |
| J.4 | Config repo wizard persistence | M | ✅ done (edit mode with pre-fill) |
| J.5 | Fan-in/fan-out demo seeds | S | ✅ done (upstream-lib → downstream-app) |
| J.6 | Config repo → pipeline dashboard mapping | S | ✅ done (config_repo_id badge on cards) |
| J.7 | Git shell-out centralized to `ExGoCD.Git` module | S | ✅ done |
| J.8 | CI: dorny/test-reporter@v2 + setup-node@v5 | S | ✅ done |
| J.9 | Quality gate: fast-fail + failure output | S | ✅ done |
| J.10 | Credo complexity fix (wizard refactor) | S | ✅ done |

---

## Part K: Infrastructure & Dependencies

### K.1 Replace shell-out git with hex `git` package
- Currently: `:os.cmd` / `System.cmd` for `git rev-parse`, `git clone` in seeds/tasks
- Plan: use `{:git, "~> 0.1"}` from hex.pm — pure Elixir, no shell-out
- Affected: `version_json.ex` (rev-parse), seed tasks (git clone), materials/poller
- **Priority**: P2 — reduces attack surface, faster, portable
- **Effort**: S — replace `System.cmd("git", ...)` with `Git.rev_parse/1` etc.

### K.2 CI: dorny/test-reporter Node deprecation
- `dorny/test-reporter@v1` uses Node 20 (EOL)
- **Fixed**: upgraded to `@v2`, `setup-node@v5` (Node 22)
- Cypress JUnit reporter configured via `CYPRESS_REPORTER` / `CYPRESS_REPORTER_OPTIONS` env vars
- **Status**: ✅ done

---

## Part L: Audit Log UI 🔴

### L.1 Current state
- `ExGoCD.AuditLog` schema: `actor`, `action`, `resource_type`, `resource_name`, `details` map
- `AuditLog.log/3` records entries (never raises)
- `AuditLog.recent/1` lists last N entries
- `AuditLog.search/1` supports filtered queries (actor, action, resource_type, date range)
- `ExGoCD.AuditLog.Events` module emits structured events (pipeline_trigger, stage_approve, etc.)
- Migration exists: `audit_logs` table
- Tests exist: `audit_log_test.exs`, `audit_log/events_test.exs`

### L.2 Missing: Searchable UI
- **No LiveView route** for `/admin/audit_log` or similar
- No search/filter form
- No pagination
- No timestamp display per entry
- No resource link (click to navigate to pipeline/stage/agent)

### L.3 Needed
| # | Item | Effort |
|---|------|--------|
| L.3.1 | `AuditLogLive` LiveView at `/admin/audit_log` | M |
| L.3.2 | Search form: actor, action, resource_type, date range | S |
| L.3.3 | Paginated results table | S |
| L.3.4 | Clickable resource links (to pipeline, stage, agent) | S |
| L.3.5 | Route in router under `live_session :gocd` | S |

**Priority**: P1. Data layer complete, UI is 2-3h of LiveView work.
**Reference**: GoCD `/go/admin/audit_log` — full CRUD audit with filters.

---

## Part M: Environment Variables — Trigger Logging, Masking, Comparison 🔴

*Cross-referenced with GoCD source: `EnvironmentVariableConfig.java`, `BuildCause.java`, `ScheduleOptions.java`, `EnvironmentVariableContext.java`*

### M.1 GoCD Source Analysis

GoCD models env vars at 4 levels with **secure/encrypted** support:

```
PipelineConfig.environmentVariables  ← EnvironmentVariablesConfig
  StageConfig.environmentVariables   ← EnvironmentVariablesConfig  
  JobConfig.environmentVariables     ← EnvironmentVariablesConfig
  BuildCause.variables               ← EnvironmentVariables (stored in PipelineInstance)
```

Each `EnvironmentVariableConfig` has:
- `name` (String, required)
- `isSecure` (boolean) — secure vars are AES-encrypted via `GoCipher`
- `value` — plain text (for non-secure)
- `encryptedValue` — AES cipher text (for secure)
- `SecretParams` — detected secret references `${SECRET[...]}`

**Trigger-time variables** (`ScheduleOptions`):
When a pipeline is triggered via "Trigger with Options", GoCD accepts:
- `variables` (plain env vars to override)
- `secureVariables` (encrypted env vars)
These are stored in `BuildCause.variables` via `addOverriddenVariables()` and become part of the `PipelineInstance.build_cause`.

**Masking in console output**:
Secure variable values are masked in console logs. GoCD uses `EnvironmentVariableContext` which tracks which vars are secure and replaces their values with `******` in output.

**Pipeline comparison**:
The `BuildCause` is serialized to JSON for the Compare API. Variables are included in the build cause, allowing comparison of which env vars were used in each pipeline run. GoCD's compare view shows material revisions + trigger message + approver. Variables flow through `BuildCauseRepresenter.toJSON()`.

### M.2 Our current state

| Level | Have? | Notes |
|-------|-------|-------|
| Pipeline env vars | ✅ | `environment_variables` map on Pipeline |
| Stage env vars | ✅ | `environment_variables` map on Stage |
| Job env vars | ✅ | `environment_variables` map on Job |
| Secure vars | 🔴 | NO `isSecure` flag, NO encryption |
| Trigger-time vars | 🔴 | `build_cause` map exists but no `variables` key |
| Console masking | 🔴 | No masking of secure values in console output |
| Compare env vars | 🔴 | Compare API doesn't show env var differences |

### M.3 Implementation Plan

| # | Item | Effort | Notes |
|---|------|--------|-------|
| M.3.1 | Add `is_secure` boolean + `encrypted_value` to env var maps | M | Schema migration for pipeline/stage/job env vars |
| M.3.2 | `ExGoCD.Cipher` module for AES encrypt/decrypt | M | Replace `GoCipher` from GoCD source |
| M.3.3 | `schedule_options` with variables + secureVariables in trigger API | M | `POST /api/pipelines/:name/schedule` body |
| M.3.4 | Store trigger variables in `build_cause.variables` | S | Already have `build_cause` map on PipelineInstance |
| M.3.5 | Console masking: `******` for secure var values | M | Filter in `BuildConsoleController` |
| M.3.6 | Masking pattern: `.*TOKEN.*`, `.*SECRET.*`, `.*PASS.*`, `.*KEY.*` | S | Configurable regex list |
| M.3.7 | Show trigger variables in Compare view | S | Include `variables` in `CompareLive` JSON |
| M.3.8 | Audit log entries for variable changes | S | Via `AuditLog.Events` |

**Priority**: P1. Core GoCD security feature. Blocking for production use.

---

## Part N: Config Repo Wizard — Two Distinct Source Types 🔴

### N.1 Problem
Current wizard has one entry point (`/admin/config_repos/new`) with source type radio buttons (GitHub Actions / GitLab CI). Missing:
- **"GoCD Pipeline Config"** source type — config repos that define GoCD pipelines (YAML/JSON pipeline-as-code)
- Clear distinction between external CI config repos and GoCD pipeline config repos

### N.2 GoCD behavior
GoCD has two separate flows:
1. **Config Repositories** (`/go/admin/config_repos`): Add a git repo containing GoCD pipeline definitions (cruise-config.xml, YAML, JSON). These are pipeline-as-code.
2. **External CI Repositories**: Map external CI workflows (GitHub Actions, GitLab CI) to GoCD pipelines.

### N.3 Needed
| # | Item | Effort |
|---|------|--------|
| N.3.1 | Add `source_type: "gocd_pipeline"` to source type selector in wizard | S |
| N.3.2 | Two distinct admin actions: "Add Pipeline Config Repo" vs "Add External CI Repo" | S |
| N.3.3 | Different wizard flow for `gocd_pipeline`: skip file config step, go to pipeline mapping | M |
| N.3.4 | Magic detection: if URL contains `.gocd.yaml` / `cruise-config.xml`, auto-detect as GoCD pipeline config | S |

**Priority**: P1. User confusion between two repo types blocks adoption.

---

## Part O: VSM Demo & Fan-In/Fan-Out Seeds ✅/🔴

### O.1 Current state
- VSM fully implemented (Part E) ✅
- Fan-in/fan-out demo seeds partially added (`priv/repo/seeds.exs`: `upstream-lib` → `downstream-app` chain) ✅
- `pipeline` material type exists in schema ✅
- `FanInResolver` validates consistency ✅

### O.2 Gaps
| # | Item | Effort | Notes |
|---|------|--------|-------|
| O.2.1 | Pre-seeded VSM demo pipeline with real git material | S | Link to `d-led/ex_gocd.git` in seeds |
| O.2.2 | Fan-in/fan-out demo visible on dashboard after seeding | S | Seeds exist; verify they produce visible pipelines |
| O.2.3 | VSM demo shows cross-pipeline dependency edges | M | Already in VSM code; needs data verification |

**Priority**: P1. Demo needed for dogfooding and user onboarding.

---

*Plan updated 2026-06-22.*
