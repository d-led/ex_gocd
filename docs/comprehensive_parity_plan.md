# Comprehensive GoCD Feature Parity Plan

*Audited 2026-06-22. Updated 2026-06-30. 861 ExUnit tests (0 skipped), 16/16 quality gate.*

> This is the single source of truth. Supersedes: `parity_roadmap_plan.md`, `vsm_parity_plan.md`, `auth_and_env_plan.md`, `external-ci-pipeline-sync-plan.md`.

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

### LiveView Pages: 18 modules

| Module | Feature |
|--------|---------|
| `DashboardLive` | Main pipeline dashboard with VSM links |
| `AgentsLive` | Agents listing & status |
| `AgentJobHistoryLive` | Job history for a single agent |
| `AgentJobRunDetailLive` | Detail view of a single agent job run |
| `JobDetailsLive` | Console, Tests, Artifacts, Materials tabs |
| `StageDetailsLive` | Stage details with breadcrumbs → VSM |
| `PipelineActivityLive` | Pipeline run history with VSM and config diff links |
| `PipelineConfigLive` | Pipeline configuration editor |
| `PipelineWizardLive` | Wizard for creating new pipelines |
| `CompareLive` | Compare two pipeline runs with env vars diff |
| `ConfigDiffLive` | Side-by-side config change diff viewer |
| `ValueStreamMapLive` | VSM: trigger info, FI/FO badges, breadcrumbs, responsive, SVG arrows |
| `MaterialsLive` | Materials (SCM) management |
| `AdminLive` | Admin settings / config / dashboard |
| `AdminSchedulingLive` | Scheduling diagnostics: pending + active jobs, agent matching, cross-links |
| `AuditLogLive` | Searchable audit log with filters and resource links |
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
| Config XML export/import | ✅ | Generate + import via :xmerl parser, UI at /admin/config_xml |
| Config versioning (snapshots) | ✅ | `ConfigVersion` schema + `ConfigSnapshot` capture (all sections, encrypted secrets). Auto-hook on mutations, history UI at `/admin/config_xml`, revert mechanism. |
| MD5 checksums | ✅ | Agent sends checksums; server stores |
| Maintenance mode | ✅ | `MaintenanceMode` GenServer with enable/disable, wired to admin UI |
| Stage cancel | ✅ | `cancel_stage/3` with transaction |
| Cycle detection | ✅ | DFS cycle detector on pipeline dependency graph |
| Dashboard API | ✅ | `GET /api/dashboard` |
| Analytics | ✅ | HTML bar charts, agent snapshots, workflow chains, VSM trends |
| Backup API | ✅ | API endpoint + admin UI with async `pg_dump` via `ExGoCD.Backup` GenServer |
| Elastic agent scheduler | ✅ | ~1100 lines: `ElasticAgentScheduler` GenServer (30s tick, k8s pod create/delete/scale/reap), `ExGoCD.K8s` client wrapper, cluster profile auto-seed. K8s-only (no Docker elastic path). |
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
| Config diff | ✅ | `config_diff/2` + `ConfigDiffLive` side-by-side viewer |
| Trigger-time variables | ✅ | GoCD-format `variables` + `secure_variables` maps accepted |
| Audit log UI | ✅ | `AuditLogLive` with search, filters, resource links |
| Scheduling admin | ✅ | `AdminSchedulingLive` with pending + active jobs, cross-links |
| Admin dropdown | ✅ | CSS-driven with JS edge guard; mobile responsive with vertical list + phx-update="ignore" |
| Plugins removed | ✅ | No plugin architecture — ex_gocd bakes in features directly. Removed from UI and nav. |
| Roles CRUD | ✅ | Schema + migration + API at `/api/admin/security/roles`. GoCD parity: `delete_role` validates not-in-use. |
| Clustering (libcluster + Horde) | ✅ | M1-M5 done: multi-node cluster, admin UI, 10 distributed singletons, Plugin.Registry + AgentSelector, OTEL process propagator, 3 example plugins (RegionalAffinity with audit log, CorpPolicy, SimpleOrgChart), PluginDemoLive at /admin/plugins, non-clustered --sname support, process-compose verified (:4000→200). |

---

## Part B: Remaining Gaps — Prioritized

### 🟡 P1: Completeness Polish

| # | Gap | Effort | Notes |
|---|-----|--------|-------|
| — | All P1 items completed | — | ✅ B1-B7, B18-B20 all done. Only B20 (admin server config UI) deferred (Docker CI 500). |

### 🟢 P2: Larger Features

| # | Gap | Effort | Notes |
|---|-----|--------|-------|
| B7 | Full config repos engine (PaC) | XL | YAML parsing, git polling, merge engine. Data model phases 0-2 done in `external-ci-pipeline-sync-plan.md`. |
| B8 | External auth (LDAP/OAuth/GitHub) | L | Ueberauth or :eldap |
| B9 | Pipeline group administration | M | ✅ `PipelineGroupPolicy` with operate/admin/view, wired into stage approval, 9 tests |
| B10-B16 | Notifications, roles, elastic profiles, cluster profiles, packages, secrets, plugins | — | ✅ All done |
| — | Elastic agent scheduler (Phase 9-10) | — | ✅ ~1100 lines: GenServer tick, k8s pod lifecycle, idle cleanup, orphan reaper, cluster profile auto-seed. K8s-only. |
| — | Clustering (libcluster + Horde) | — | ✅ M1-M5 done: multi-node cluster, admin UI, 10 distributed singletons, plugin registry, OTEL propagator |
| — | Enhanced compare dialog (Phase 11) | M | ✅ Any-two-instance pickers, side-by-side materials/env-vars diff, config-changed detection. `CompareLive` with `/compare/:name/:from/with/:to` routes. |
| — | Embedded stats (Phase 11b) | S | ✅ Pass rate, MTTR, avg build/wait on pipeline activity; pass rate + avg duration summaries on stage trends tab. |
| — | Gantt chart view (Phase 12) | M | Timeline + dependency arrows. Candidate: `phoenix_live_gantt` |
| — | Auth plugin (Ueberauth/LDAP) in plugins/managed/ | L | Plugin architecture ready, not started |
| — | Org Hierarchy + Pipeline Grouper integration | M | ✅ PipelineGrouper wired into DashboardLive.grouping_data via Plugin.Registry. Fallback to static grouping when no plugin registered. 3 tests. SimpleOrgChart already registered as :org_hierarchy + PipelineGroupPolicy uses org_hierarchy_access?. |

### 🔵 P3: Analytics — ✅ Done

All B17-B21 complete: agent transitions schema, utilization snapshots (5-min GenServer), workflow chains (9 tests), VSM trends, HTML bar charts on all tabs. Contex dependency removed 2026-06-28 — all charts are now unified HTML bars.

### ⚪ P4: Low Priority / Not Started

| # | Gap | Effort | Status |
|---|-----|--------|--------|
| B22 | Feeds XML (pipeline/stage/job RSS — CcTray parity) | S | ✅ CCTray XML + Atom feeds at `/api/feeds/pipelines.xml` |
| B23 | Mailserver config | S | ✅ `config :ex_gocd, :mailer_from` + `:site_url` in config.exs, `from()/site_url()` helpers |
| B24 | Site URLs config | S | ✅ `config :ex_gocd, :site_url` used by mailer + pipeline detail links |
| B25 | Job timeout config | S | ✅ Per-job `timeout` field, console inactivity monitor, "never" support |
| B26 | Notification filters (per-user, per-event) | S | ✅ Schema + CRUD API + dispatch wired to Mailer, 7 tests |
| B27 | SCMs API | S | ✅ `ExGoCDWeb.API.SCMController` — GET /api/admin/scms lists all unique materials across pipelines |
| B28 | Permissions API | S | ✅ Dynamic: roles + pipeline group permissions from DB |
| B29 | Artifact stores API | S | ✅ Full CRUD |
| B30 | Server health API | S | ✅ `/server_health_messages` with real health checks |

---

## Part C: Priority Matrix (2026-07-01)

| Priority | Items | Effort | Impact |
|----------|-------|--------|--------|
| **P0** | — | — | ✅ DONE |
| **P1** | — | — | ✅ DONE |
| **P2** | Embedded stats, Enhanced compare | S-M | ✅ DONE |
| **P2** | Gantt chart | M | 1 UI polish item remaining |
| **P2** | Full config repos engine (PaC) | XL | Pipeline-as-code from git |
| **P2** | External auth plugin (Ueberauth) | L | LDAP/OAuth/GitHub login |
| **P3** | — | — | ✅ DONE (Analytics) |
| **P4** | — | — | ✅ DONE (B22-B30) |

## Part D: Build & Quality

- **Tests**: 886 ExUnit tests (0 skipped), Go agent tests pass, Cypress E2E suite (116 tests, 16 specs)
- **Quality gate**: compile `--warnings-as-errors` clean, `mix format --check-formatted` clean, Credo, Sobelow pass
- **Compile**: clean with `--warnings-as-errors` on all files
- **Go agent**: `go build`, `go vet`, `go test ./...` — all clean

---

## Part E: VSM — Fully Shipped ✅

See [vsm_parity_plan.md](vsm_parity_plan.md) for full details. All 5 phases complete.

### VSM Link Audit (vs GoCD source `spark_routes.ts`, 2026-06-30)

GoCD links to VSM from these locations:

| GoCD Link Point | Route | ex_gocd Status |
|-----------------|-------|----------------|
| Pipeline activity → VSM per run (`getVSMLink` in run info widget) | `/go/pipelines/value_stream_map/:name/:counter` | ✅ "VSM" link on each counter row in `PipelineActivityLive` |
| Dashboard → VSM (pipeline card) | `/go/pipelines/value_stream_map/:name/:counter` | ✅ "VSM" link on each pipeline instance card |
| Stage details → VSM (breadcrumb counter link) | `/go/pipelines/value_stream_map/:name/:counter` | ✅ Breadcrumbs link to VSM for pipeline counter |
| **Material → material VSM** (`SparkRoutes.materialsVsmLink(fingerprint, revision)`) | `/go/materials/value_stream_map/:fingerprint/:revision` | ❌ **Not yet implemented** |
| Stage overview → VSM (`stage_overview_shim_for_vsm.tsx`) | `/go/pipelines/value_stream_map/:name/:counter` | ❌ Not applicable (GoCD-specific D3 shim) |

**Gap**: Material VSM — GoCD renders a "VSM" link next to each material modification showing that revision in the value stream. Needs a `MaterialVSM` LiveView or a parameterized VSM that accepts `?fingerprint=X&revision=Y`.

---

## Part F: Analytics — ✅ Done (2026-06-28)

Parity with `gocd-analytics-plugin`. All dashboard types implemented:

- **Global**: Pipeline wait times, agent jobs, all-pipeline table
- **Pipelines**: Per-pipeline analytics with pass/fail rates
- **Pipeline Detail**: Build duration trends, stage breakdowns
- **Agents**: Per-agent job outcomes, utilization snapshots, type badges
- **VSM Trends**: Run duration distribution across counters
- **Charts**: All HTML horizontal bar charts (Contex SVG removed — unified style)

The GoCD analytics plugin provides separate dashboard pages (not embedded in stage/job views). Our `/analytics` page matches this pattern. Embedded stats in stage/job detail pages would be a nice-to-have.

---

## Part G: Remaining Items — Prioritized (2026-06-30)

### 🟡 P2: Medium Effort — UI Polish

| # | Item | Effort | Notes |
|---|------|--------|-------|
| G1 | Enhanced compare dialog | M | Any-two-instance pickers, side-by-side diff. CompareLive already exists with counter pickers + env vars + modifications table. |
| G2 | Gantt chart dependency arrows | M | GanttLive exists at `/gantt` with SVG bars. Needs upstream/downstream arrows between pipeline runs. |
| G3 | Embedded pipeline/stage stats | S | Charts in detail pages, not just `/analytics`. |

### 🔴 P2: Large Effort

| # | Item | Effort | Notes |
|---|------|--------|-------|
| G4 | Full config repos engine (PaC) | XL | YAML/JSON parsing, git polling, merge engine. Data model done in `external-ci-pipeline-sync-plan.md`. |
| G5 | External auth plugin (Ueberauth) | L | Separate Phoenix app in `plugins/managed/`. LDAP/OAuth/GitHub. Plugin architecture ready. |

### ✅ Done (was P2)

| # | Item | When | Notes |
|---|------|------|-------|
| — | Material VSM link | — | ✅ Routes at `/materials/value_stream_map/:fingerprint/:revision` |
| — | Org Hierarchy + PipelineGrouper | 2026-06-30 | ✅ SimpleOrgChart → PipelineGroupPolicy. PipelineGrouper wired into DashboardLive with fallback. 3 tests. |

### ❌ Deferred / Removed

| Item | Reason |
|------|--------|
| Docker elastic agent path | K8s-only. No Docker API client planned. |
| K8s agent config admin UI | Cluster profile auto-seed works via DB. |

---

## Part H: Build & Quality Summary

- **Tests**: 886 ExUnit (0 skipped), Go agent clean, Cypress 108 tests (15 specs)
- **Quality gate**: compile `--warnings-as-errors` clean, Credo 0 issues, Sobelow 0 findings
- **LiveView pages**: 19 modules
- **API controllers**: 20 controllers, 83 actions
- **Clustering**: M1-M5 done — libcluster+Horde, 10 distributed singletons, OTEL propagator
- **Plugin architecture**: 5 behaviours, Plugin.Registry, AgentSelector wired, PipelineGrouper wired, 3 example plugins
- **Single source of truth**: this file. Supersedes all other plan docs.
