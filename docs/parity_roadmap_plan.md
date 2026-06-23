# GoCD Parity Implementation Roadmap

This document outlines the design and implementation steps for completing the missing GoCD parity features in the **ex_gocd** rewrite.

---

## Phase 1: SCM Polling & Modification Engine ✅ DONE

To support automatic pipeline triggering, the server must query VCS repositories periodically and store commits in the database.

### 1. Database Schema ✅
`modifications` table tracks SCM changes (material_id, revision, committer_name, committer_email, comment, modified_time).

### 2. SCM Polling Service (`ExGoCD.Materials.Poller`) ✅
GenServer polling all git materials on a configurable interval; uses `GitClient` (SystemImpl / MockImpl) to detect new revisions and stores `Modification` records.

### 3. Pipeline Trigger Hooks ✅
New modification → save to DB → find pipelines using the material → trigger via `Pipelines.trigger_pipeline/1`.

---

## Phase 2: Fan-In Resolution & Value Stream Mapping ✅ DONE

Enforcing revision consistency across pipeline dependencies.

### 1. Pipeline Material Revisions (PMR) Schema ✅
`pipeline_material_revisions` join table: pipeline_instance_id, material_id, modification_id (optional), parent_pipeline_instance_id (optional).

### 2. Fan-In Backtracking Algorithm ✅
`FanInResolver.verify_consistency/1` enforces that shared SCM materials resolve to the same revision across all upstream dependency pipelines before allowing a downstream trigger.

---

## Phase 3: Advanced Scheduling & Concurrency Locks ✅ DONE

### 1. Environment and Resource Matching ✅
`ExGoCD.Scheduler` validates agent environments and resource tags against job config requirements before assignment.

### 2. Concurrency Locks ✅
`pipeline_locked?/1` implements all three behaviors:
- `none` → never locked
- `unlockWhenFinished` → locked while any stage is building
- `lockOnFailure` → locked while building OR if `pipeline.locked == true` (set on stage failure); manual unlock via `unlock_pipeline/1`

Lock lifecycle managed in `do_complete_stage/3`: sets `locked: true` on failure for `lockOnFailure` pipelines.

---

## Phase 4: Timer-Triggered Pipelines ✅ DONE

Pipeline configs have a `timer` field (cron spec string, e.g. `"0 0 22 ? * MON-FRI"`) and `timer_only_on_changes` flag.

### 1. Schema Update ✅
Added `timer_only_on_changes` boolean field to `pipelines` table.

### 2. `ExGoCD.Materials.TimerScheduler` GenServer ✅
- GenServer starts on application boot, subscribing to `pipelines:updates`.
- Computes Quartz-style cron schedules, executing ticks to trigger jobs.
- Implements `timer_only_on_changes` checking of SCM modifications since last run.

---

## Phase 5: Manual Stage Gate ✅ DONE

`approval_type: "manual"` is stored and validated on `Stage`.

### 1. Gate in `trigger_next_stage` ✅
Stages with manual gates transition to `"Awaiting"` state and do not schedule jobs until approved.

### 2. `Pipelines.approve_stage/3` ✅
Approve stage actions transition stages to `"Building"` and dispatch jobs to the `Scheduler`.

### 3. API / LiveView ✅
Exposed REST endpoint `POST /go/pipelines/:pipeline_name/:counter/:stage_name/run` and added visual "Approve" actions to the UI.

---

## Phase 6: REST API Parity & Personal Access Tokens (PATs) ✅ DONE

### 1. Version, Pause, and Lock APIs ✅
Exposed REST endpoints to check version status, pause/unpause pipelines, and unlock active runs.

### 2. Schedule Trigger Overrides ✅
Added options to trigger pipelines with customized SCM revisions and environment variables.

### 3. Personal Access Tokens ✅
Implemented user token generation, hashes storage, Bearer authentication plug, and token management APIs.

---

## Phase 7: SCM Post-Commit Webhooks ✅ DONE

### 1. Webhook Receivers ✅
Implemented GitHub and GitLab webhook endpoints with secret token verification and payload signature verification.

### 2. Git Notification API ✅
Exposed `/api/admin/materials/git/notify` endpoint to trigger repository polling manually.

---

## Remaining Gaps vs. Legacy GoCD

All 7 previously identified gaps have been addressed. Summary:

1. **Multi-SCM Materials** ✅ — `ScmClient` dispatches to Git, SVN, Hg, P4, TFS via `SystemImpl`/`MockImpl`. Poller queries all supported types.
2. **Configuration Templates & Parameters** ✅ — `ExGoCD.Params` interpolation engine (`#{param}`), `pipelines.template_id` FK, `resolve_template_stages/1`.
3. **Pipeline-as-Code (Config Repos)** ✅ — `config_repos` table, `ExGoCD.ConfigRepos` context, JSON parser, upsert logic.
4. **Daemon / Parallel Jobs** ✅ — `run_on_all_agents` (per-idle-agent instances), `run_instance_count` (N parallel instances), `Agents.count_idle/0`.
5. **Granular RBAC** ✅ — `pipeline_group_permissions` table, role hierarchy (viewer/operator/admin), `can_access_pipeline_group?/3`.
6. **System & Storage Monitors** ✅ — `DiskSpace` GenServer, df-based free space check, threshold broadcasting.
7. **Artifact Checksums** ✅ — Server-side MD5 computation on upload, manifest append, zip directory checksums.

### Remaining minor gaps for future iterations:

- **TFS/Azure DevOps deep integration**: TFS material stub exists, but full tf/rest polling not implemented.
- **Pluggable SCM**: Extension point exists in schema but no plugin system.
- **Package materials** (NuGet, Yum, APT): Schema supports `type: "package"` but not polled.
- **FetchArtifact task type**: Downstream fetch with checksum verification exists as schema but not wired.
- **Pipeline groups UI management**: RBAC permissions are API/DB-backed but no admin UI for managing group permissions.
- **Ecto query performance review & testing**: Audit all Ecto queries for N+1, missing indexes, eager/join inefficiencies. Write isolated performance tests with benchmarks for critical query paths (VSM graph, dashboard, pipeline activity, scheduler polling). Review preloads, subqueries, and join strategies.
- **VSM: eliminate hardcoded mock data**: "2 hours ago" timestamps, fake commit info (`"Initial commit for repository integration"`, `"exgocd-admin <admin@exgocd.local>"`). Wire real modification data from DB into VSM nodes for both DB and mock paths.
- **VSM: fan-in count bug on source pipelines**: `FI:3` shown on upstream-lib (fan-out source with 0 incoming edges). Should be hidden or show FI:0. `count_fan_in/1` needs to return 0 for pipelines with no dependency-material parents.
- **VSM: trigger URL text clipping**: Material URL in trigger info truncated mid-string (`"https://github.com/d-led/ex_go"`). Use CSS `truncate` with adequate width or `title` attribute.
- **VSM: un-run pipeline status default**: Pipeline instances with no runs show "Unknown" instead of "Not Yet Run" (grey). Default status should match GoCD's `NullStage` behavior.
- **VSM: SVG arrow hover/tap highlighting**: Arrows connecting VSM nodes don't highlight on hover/tap. Needs JS `VSMGraph` hook enhancement to add `mouseenter`/`mouseleave` listeners on SVG paths.
- **Test isolation: scheduler sandbox flakiness**: Webhook (7) and poller (3) tests pass in isolation but time out in full suite due to cross-test sandbox connection contention. Fixed `wait_for_scheduler_queue/0` to check `pending_count == 0` but may need further hardening — consider `Ecto.Adapters.SQL.Sandbox.checkout/2` in scheduler operations or dedicated test mode for scheduler GenServer.

---

## Phase 8: Scheduling Checker Pipeline ✅ DONE

GoCD's `SchedulingCheckerService` runs a composite chain of checks before allowing any pipeline trigger, stage schedule, or rerun. ex_gocd now has the structured checker pattern fully wired.

### Checker status:

| Checker | Status | Notes |
|---|---|---|
| `AboutToBeTriggeredChecker` | ✅ Done | ETS-based `TriggerMonitor` debounce |
| `PipelinePauseChecker` | ✅ Done | `pipeline.paused` in `trigger_pipeline/1` |
| `PipelineLockChecker` | ✅ Done | `pipeline_locked?/1` with 3 lock behavior modes |
| `StageActiveChecker` | ✅ Done | `StageActive` composite checker |
| `PipelineActiveChecker` | ✅ Done | `PipelineActive` checker on rerun-stage |
| `StageLockChecker` | ✅ Done | `StageLock` concurrency checker |
| `StageManualTriggerChecker` | ✅ Done | `StageManualTrigger` checker |
| `OutOfDiskSpaceChecker` | ✅ Done | Wired via `DiskSpace` monitor |
| `StageAuthorizationChecker` | ✅ Done | Via `ExGoCD.Policies` |
| `ManualPipelineChecker` | ✅ Done | Blocks auto-trigger on manual first stages |

