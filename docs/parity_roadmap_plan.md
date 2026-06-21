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

While the core pipeline execution, scheduling, agent tracking, webhooks, and REST APIs are complete, the following gaps remain to reach full parity with legacy GoCD:

1. **Multi-SCM Materials**: Git is currently the only supported VCS. SVN, Mercurial (Hg), Perforce (P4), TFS, and pluggable custom SCMs are not yet implemented.
2. **Configuration Templates & Parameters**: GoCD templates and parameter interpolation (`#{param_name}`) are not supported; pipelines must be defined directly.
3. **Pipeline-as-Code (Config Repos)**: Support for syncing pipeline configurations dynamically from Git repositories using YAML/JSON templates is missing.
4. **Daemon / Parallel Jobs**:
   - `run_on_all_agents` (to schedule job instances on all agents for cleanups).
   - `run_multiple_instance` (to split a job into parallel runs).
5. **Granular RBAC**: Environment-level and pipeline-group-level granular permissions (Operate, View, Admin) are checked via basic policies, but lack a dynamic user-customizable definitions store.
6. **System & Storage Monitors**: Low disk space detectors and automatic artifact cleanup/purging policies are not implemented.
7. **Artifact Checksums**: Calculated checksum manifests (MD5/SHA) for artifact integrity verification on `FetchArtifact` tasks are not enforced.
