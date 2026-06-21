# Comprehensive GoCD Feature Parity Plan

*Generated 2026-06-21 after cross-repo review of `gocd`, `api.go.cd`, `docs.go.cd`, and `gocd-analytics-plugin`.*

---

## Part A: Current State (ex_gocd)

### ✅ Done (7 phases per parity_roadmap_plan.md)
| # | Feature | Notes |
|---|---------|-------|
| 1 | SCM Polling & Modification Engine | Git polling, modification storage, trigger on new revision |
| 2 | Fan-In Resolution & VSM | FanInResolver backtracking, VSM API |
| 3 | Advanced Scheduling & Concurrency Locks | Env/resource matching, pipeline lock policies |
| 4 | Timer-Triggered Pipelines | Cron schedules, timer_only_on_changes |
| 5 | Manual Stage Gate | approval_type: "manual", approve_stage API/UI |
| 6 | REST API Parity & PATs | Pause/unpause/schedule, access tokens, Bearer auth |
| 7 | SCM Post-Commit Webhooks | GitHub, GitLab webhooks, git notify API |

### ✅ Done (additional)
- Agent registration & management API (v7-compatible)
- Agent remoting API (ping/get_work/report_status)
- Artifacts upload/download API (`/files/`, `/remoting/files/`)
- Basic job details page (console log + artifacts tabs)
- Stage details page
- Dashboard LiveView with pause/unpause
- Pipeline config LiveView (wizard)
- Admin LiveView (cleanup stuck jobs)
- Pipeline compare page
- Pipeline activity page
- Audit log (immutable context)
- Value stream map API
- Template schema (basic)
- Config repo schema (basic)
- Multi-SCM client (Git, SVN, Hg, P4, Tfs - SystemImpl + MockImpl)
- Params engine (`#{param}` interpolation)
- Agent job run history page
- 425 tests, 0 Credo F-issues, 0 Sobelow findings

---

## Part B: Missing Features — Prioritized

### 🔴 P0: Core User-Visible Parity Gaps

#### B1. Job Details: Fake Console & Missing Tests Tab
- **Current**: JobDetailsLive shows mock data when no AgentJobRun exists ("fake step")
- **Root cause fixed**: Scheduler `db_pending_count` bug fixed — jobs now get assigned
- **Still needed**:
  - **Tests tab**: Iframe showing `index.html` from `testoutput/` folder (JUnit XML → HTML via XSLT)
  - **Console live streaming**: Real-time console log with timestamps, folding, auto-scroll
  - **Materials tab**: Show material revisions that triggered this pipeline

#### B2. Test Report Generation (UnitTestReportGenerator parity)
- GoCD merges JUnit XML files → XSLT transform → `testoutput/index.html`
- **Plan**:
  1. Accept JUnit XML artifacts from agent (agent already uploads artifacts)
  2. On job completion, scan `testoutput/` for `*.xml` files
  3. Merge into single `<all-results>` XML structure
  4. Transform via XSLT to `index.html` (bundle `unittests.xsl` as static asset)
  5. Serve via artifacts controller or embed in Tests tab iframe

#### B3. Artifact Tree Browser
- GoCD renders recursive directory tree with expand/collapse, file download links
- **Current**: Basic flat artifact listing in JobDetailsLive template
- **Plan**:
  1. Add recursive directory scanning endpoint: `GET /files/.../*.json`
  2. Build collapsible tree UI component in LiveView (or vanilla JS)
  3. Each file: download link; each folder: expandable

#### B4. Console Log Quality
- GoCD console: timestamps, folding, fullscreen, live tail via `ConsoleStreamer`
- **Current**: Plain `<pre>` block
- **Plan**:
  1. Send timestamps from agent (already prefixed `HH:mm:ss.SSS` in Go agent)
  2. Add log folding for repeated lines
  3. Add fullscreen toggle
  4. Live tail via PubSub (already partially wired — `subscribe_console` exists)

---

### 🟡 P1: Artifact Integrity & Cleanup

#### B5. Artifact MD5 Checksums
- GoCD: `md5.checksum` in `cruise-output/`, verified on fetch by downstream jobs
- **Plan**:
  1. Agent sends checksum file alongside artifacts (agent already computes MD5)
  2. Server stores checksums in DB (`artifact_checksums` table)
  3. GET artifacts: serve checksum as header or separate endpoint
  4. Fetch artifact task: verify checksum before saving

#### B6. Fetch Artifact Task
- GoCD downstream jobs run `<fetchartifact>` to pull artifacts from upstream
- **Plan**:
  1. Add `fetch_artifact` task type to Job schema
  2. Agent executes: fetch from server via `/files/...` API, verify checksum, extract to working dir
  3. Agent command in protocol: `{"command": "fetch_artifact", "source": "pipeline/stage/job", "src": "path", "dest": "."}`

#### B7. Artifact Auto-Cleanup / Disk Space Monitor
- GoCD: `GoDiskSpaceMonitor`, `ArtifactsDiskSpaceFullChecker`, auto-purge policies
- **Plan**:
  1. GenServer polling disk usage of `ARTIFACTS_DIR`
  2. Configurable thresholds: warning (yellow) and critical (red)
  3. Auto-purge: delete oldest artifacts when below critical threshold
  4. Admin UI: show disk usage, configure thresholds, manual purge

---

### 🟡 P2: API Parity (REST Endpoints)

#### B8. Missing REST APIs (by category)

**Pipeline APIs (⚠️ partial → ✅ full):**
- `GET /api/pipelines/:name/history` — pipeline instance history
- `GET /api/pipelines/:name/:counter` — single pipeline instance
- `POST /api/pipelines/:name/:counter/comment` — comment on instance

**Stage APIs (❌):**
- `GET /api/stages/:pipeline/:counter/:stage/:counter` — stage instance
- `POST /api/stages/:pipeline/:counter/:stage/cancel` — cancel stage
- `GET /api/stages/:pipeline/:stage/history` — stage history
- `POST /api/stages/:pipeline/:counter/:stage/:counter/run-failed-jobs`
- `POST /api/stages/:pipeline/:counter/:stage/:counter/run-selected-jobs`

**Job APIs (⚠️ partial → ✅ full):**
- `GET /api/jobs/:pipeline/:counter/:stage/:counter/:job` — job instance
- `GET /api/jobs/:pipeline/:stage/:job/history` — job history

**Pipeline Config Admin APIs (❌):**
- `GET/POST/PUT/DELETE /api/admin/pipelines/:name` — full CRUD
- `PUT /api/admin/pipelines/:name/extract_to_template`

**Template Config Admin APIs (❌):**
- Full CRUD for templates + authorization

**Dashboard API (❌ → P3):**
- `GET /api/dashboard` — JSON dashboard (currently LiveView-only)

**Environments (❌):**
- Full CRUD for environments

**Pipeline Groups (❌):**
- Full CRUD for pipeline groups

**Roles & Auth (❌):**
- Roles CRUD, auth configs CRUD, system admins

**Users (❌):**
- User CRUD API

**Config Repos (❌ → P3):**
- Full CRUD for config repos

**Backups (❌ → P3):**
- Backup schedule, status, config

**Other (❌ → P3):**
- Mailserver config, site URLs, artifact config, job timeout, encryption, server health, maintenance mode, notification filters, feeds XML, plugin info, package repositories, SCMs, elastic profiles, cluster profiles, secret configs, artifact stores, materials API, permissions API

---

### 🟡 P2: Configuration Validation

#### B9. Pipeline Graph Cycle Detection
- GoCD: DFS cycle detector on pipeline dependency graph
- **Plan**:
  1. Implement `ExGoCD.Pipelines.CycleDetector`
  2. DFS on material dependencies
  3. Validate on pipeline save/update
  4. Return clear error message with cycle path

#### B10. Configuration XML Import/Export
- GoCD: `cruise-config.xml` full import/export
- **Plan** (lower priority — DB-backed is fine):
  1. `GET /go/api/admin/config.xml` → serialize DB state to XML
  2. `POST /go/api/admin/config.xml` → parse XML, validate, import

---

### 🟢 P3: Advanced Features

#### B11. Full Config Repos (Pipeline-as-Code)
- Schema exists but sync engine missing
- GoCD: watches git repos for `.gocd.yaml` / `.gocd.json`, parses, merges
- **Plan**:
  1. Config repo polling GenServer
  2. YAML/JSON parser for GoCD pipeline format
  3. Merge engine (config repo definitions vs local DB)
  4. Conflict resolution UI

#### B12. Environments
- GoCD: environment = named group of pipelines + agents; can gate pipeline triggers
- **Plan**:
  1. Schema: `environments` table, join tables for pipelines + agents
  2. Agent assignment: agent in env `production` only gets jobs from `production` pipelines
  3. Pipeline trigger restriction: only within same environment

#### B13. External Auth (LDAP/OAuth/GitHub)
- GoCD: plugin-based auth, supports LDAP, GitHub OAuth, Google OAuth, etc.
- **Plan** (bodyguard-based):
  1. OAuth2 flow via `Ueberauth` or custom
  2. GitHub OAuth provider
  3. LDAP connector via Erlang `:eldap`
  4. Store auth config in DB

#### B14. Pipeline Group Administration
- GoCD: delegate admin of specific pipeline groups to non-admin users
- **Plan**:
  1. Schema: `pipeline_group_admins` join table
  2. Policy check: `permit?(user, :admin_pipeline_group, group_name)`
  3. UI: group admin management page

#### B15. Notifications
- GoCD: email notifications on pipeline/stage events, per-user notification filters
- **Plan**:
  1. Swoosh-based email sending (already configured)
  2. Notification filter schema (per user: pipeline, stage, event types)
  3. Event subscription: PubSub → check filters → send email

---

### 🔵 P4: Analytics Plugin (Built-In)

The `gocd-analytics-plugin` is a GoCD plugin that provides pipeline/build analytics. Rather than building a separate plugin, integrate the analytics directly into ex_gocd as a first-class feature.

#### B16. Analytics Data Model

GoCD plugin has its own PostgreSQL database with these tables (via `db/DBAccess.java` + DAOs):

| Table | Purpose | Our Equivalent |
|-------|---------|---------------|
| `pipelines` | Pipeline name, avg_wait_time_secs, avg_build_time_secs | Add materialized view or computed columns to our `pipelines` |
| `stages` | Stage build time per stage name | Our `stage_instances` + aggregation |
| `jobs` | Job build/wait time per job name | Our `job_instances` + aggregation |
| `agents` | Agent last transition time, hostname | Our `agents` table |
| `agent_transitions` | Agent state changes (idle→building→idle) | New: `agent_state_transitions` table |
| `agent_utilization` | Utilization snapshots per agent | New: `agent_utilizations` table |
| `material_revisions` | Material revision details per pipeline | Our `modifications` + `pipeline_material_revisions` |
| `pipeline_workflows` | Workflow = chain of pipelines through dependencies | New: `pipeline_workflows` table |
| `workflows` | Workflow = group of pipeline instances forming a VSM | New: `workflows` table |

#### B17. Analytics Views (AvailableAnalytics parity)

All 11 analytics from GoCD plugin, mapped to Elixir:

| # | Analytics | Type | Input | Query/Logic |
|---|-----------|------|-------|-------------|
| 1 | **Pipeline Build Time** | pipeline | pipeline_name, start, end | `AVG(stage_instances.completed_at - stage_instances.started_at)` grouped by pipeline, date |
| 2 | **Stage Build Time** | stage | pipeline_name, stage_name, start, end | `AVG(stage_instances.completed_at - stage_instances.started_at)` for specific stage |
| 3 | **Jobs with Highest Wait Time** | job | start, end | `AVG(job_instances.started_at - job_instances.scheduled_at)` per job, sorted DESC |
| 4 | **Job Build Time** | job | pipeline_name, stage_name, job_name, start, end | `AVG(job_instances.completed_at - job_instances.started_at)` for specific job |
| 5 | **Pipelines with Highest Wait Time** | dashboard | start, end | `AVG(min_stage_start - pipeline_trigger_time)` per pipeline, sorted DESC |
| 6 | **Agents with Highest Utilization** | dashboard | start, end | `SUM(job_build_time) / total_elapsed_time` per agent, sorted DESC |
| 7 | **Jobs with Highest Wait Time on Agent** | drilldown | agent_uuid, start, end | `AVG(wait_time)` for jobs on specific agent |
| 8 | **Job Build Time on Agent** | drilldown | agent_uuid, start, end | `AVG(build_time)` for jobs on specific agent |
| 9 | **Agent State Transition** | agent | agent_uuid, start, end | Timeline of state changes: idle→building→idle with durations |
| 10 | **VSM Trend Across Multiple Runs** | vsm | vsm_graph, start, end | For each VSM stage, collect lead times per run, plot trend |
| 11 | **VSM Workflow Time Distribution** | drilldown | workflow_id, start, end | Time spent in each VSM stage for a specific workflow |

#### B18. Analytics Implementation Plan

**Phase A: Data Collection (built into existing code)**
1. **Agent state transitions**: When agent state changes in `Agents.update_agent_state/2`, write to `agent_state_transitions` table
2. **Agent utilization**: Periodic GenServer snapshot (every 5 min): for each agent, compute `utilization = busy_time_in_window / window_duration`
3. **Pipeline workflows**: On pipeline completion, compute workflow chain via `PipelineWorkflowDAO`-style traversal

**Phase B: Aggregation Queries**
- Create `ExGoCD.Analytics` context module
- Implement each query as a function with date filtering
- Return JSON-shaped results for API/UI consumption

**Phase C: Analytics API**
- `GET /api/analytics/:type?id=:id&pipeline_name=:name&start=:start&end=:end`
- Single endpoint that dispatches to correct executor by analytics ID
- Response format matches GoCD analytics plugin JSON shape for chart library compatibility

**Phase D: Analytics UI**
- Add "Analytics" tab to main navigation
- Dashboard-level analytics (Pipelines with Highest Wait Time, Agents with Highest Utilization)
- Pipeline-level drilldown (Pipeline Build Time chart → click → Stage Build Time)
- Agent-level drilldown (Agent State Transition timeline, Job times on agent)
- VSM analytics (trend across runs, workflow time distribution)
- Render with Chart.js or similar charting library

---

## Part C: Implementation Priority Matrix

| Priority | Group | Effort | Impact | Dependencies |
|----------|-------|--------|--------|--------------|
| **P0** | Tests tab + test report gen | M | High — visible on every build | Artifacts working |
| **P0** | Real console log (live, timestamps) | S | High — user expectation | PubSub wiring exists |
| **P0** | Artifact tree browser | M | High — primary artifact UX | Directory scanning |
| **P1** | MD5 checksums | S | Medium — data integrity | Agent already computes |
| **P1** | Fetch artifact task | M | Medium — downstream jobs | Checksums + agent protocol |
| **P1** | Artifact auto-cleanup | M | Medium — prod ops | Disk monitor |
| **P1** | Console activity monitor | S | Medium — hang detection | Agent cancel command |
| **P2** | Pipeline/Stage/Job history APIs | M | Medium — API completeness | Existing schemas |
| **P2** | Pipeline config admin APIs | L | Medium — automation | Pipeline CRUD exists |
| **P2** | Template + config repo admin APIs | L | Medium | Schema exists |
| **P2** | Cycle detection | S | Medium — safety | Existing dependency graph |
| **P2** | User/role/admin APIs | L | Medium — enterprise | Bodyguard integration |
| **P3** | Full config repos engine | XL | High — PaC feature | YAML parsing, merge |
| **P3** | Environments | L | Medium | Schema + agent matching |
| **P3** | External auth (OAuth/LDAP) | L | Low — enterprise | Ueberauth/:eldap |
| **P3** | Notifications | M | Medium | Swoosh + PubSub |
| **P3** | Backups | M | Low-medium | DB dump + artifact archive |
| **P3** | Maintenance mode | S | Low | Flag + middleware |
| **P4** | Analytics data collection | M | Medium | Agent state tracking |
| **P4** | Analytics aggregation queries | M | Medium | Data collected |
| **P4** | Analytics API | S | Medium | Queries implemented |
| **P4** | Analytics UI (charts) | L | High — user delight | API + chart library |

---

## Part D: Quick Wins (This Session)

1. **Remove mock data from JobDetailsLive** — scheduler fix means real jobs run now
2. **Add "Tests" tab to JobDetailsLive** — check `testoutput/` for `index.html`, iframe it
3. **Add live console timestamps** — agent already sends them, just render
4. **Add artifact tree** — recursive directory listing endpoint + collapsible UI
5. **Add cancel pipeline button to dashboard** — `Pipelines.cancel_pipeline/1` → agent cancel signal

---

## Part E: gocd-analytics-plugin Architecture Summary

The plugin is a standard GoCD analytics plugin (Java/Gradle) with:
- **`AnalyticsPlugin.java`**: Plugin entry point, implements `AnalyticsPlugin` interface
- **`AvailableAnalytics`**: Enum of 11 analytics types with ID, title, and category
- **`AnalyticTypes`**: Constants for request parameters (context, metric, pipeline_name, etc.)
- **Executor pattern**: Each analytics type has an executor class (e.g., `PipelineBuildTimeExecutor`)
- **`AnalyticsExecutorSelector`**: Routes request by analytics ID to correct executor
- **DAO layer**: Each domain model has a DAO (PipelineDAO, StageDAO, JobDAO, AgentDAO, etc.)
- **Database**: Separate PostgreSQL DB (`DBAccess` → `PostgresqlDatabase`), schema migrations in `db/`
- **Web UI**: JavaScript frontend (`javascripts/`) with chart rendering, plugin settings page
- **Workflow allocation**: Complex logic for tracing pipeline dependencies (`WorkflowAllocator` hierarchy)
- **Data purging**: `DataPurgeScheduler` + `DataPurger` for cleaning old analytics data

**Integration approach for ex_gocd**: Build analytics directly into the Phoenix app, not as a separate plugin. Use our existing Ecto schemas, add aggregation queries in a new `ExGoCD.Analytics` context, and build the UI as LiveView components.

---

## Appendix: GoCD API → ex_gocd Status Summary

Total GoCD API endpoints: ~130 across 41 categories.
ex_gocd implemented: ~15 endpoints (Agents, Artifacts, Agent Remoting, Pipeline Ops, Version, Jobs schedule, Webhooks).
Coverage: ~12%.
Priority endpoints to add: Job instance/history, Stage instance/history, Pipeline instance/history, Pipeline config admin, Templates admin, Users, Dashboard API, Environments.
