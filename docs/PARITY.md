# ex_gocd — Unified Feature Parity Plan

> Single source of truth. Supersedes all previous plan/roadmap/status documents.
> Last audited: 2026-07-06. 900+ tests. 67 controllers. 21 LiveView pages. 20 GenServers. 40 migrations.

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
| Test Reports | ✅ JUnit XML → HTML | ✅ JobDetailsLive tests tab | ✅ test_report.ex |
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

### Remaining Gaps (10)
6. A5: Backup config API
7. A6: Backup status tracking
8. A4: Pipeline groups admin API
9. C2: Pluggable SCM full CRUD
10. C1: Packages CRUD API

### Phase 3: Features (M-L)
11. B4: Agent UI search/filter/sort
12. A2: Agent health monitoring
13. D1: Artifact caching Phase 1

### Phase 4: Stretch (L-XL)
14. D2: Docker elastic agent path

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
| `mix test` | ✅ 890 passed |
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

### Reference Docs (kept)

- `architecture_and_parity.md` — condensed parity summary + architecture
- `module_mapping.md` — Elixir ↔ GoCD Java file mapping
- `gocd_console_log_format.md` — console stream format
- `gocd_testing_analysis.md` — GoCD Java test patterns
- `mock_mode.md` — UI dev without DB
- `plugin_authoring.md` — plugin development guide
- `pubsub_and_realtime_views.md` — PubSub pattern docs
- `sobelow-justifications.md` — security scanner justifications
