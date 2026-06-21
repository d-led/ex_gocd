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

## Phase 4: Timer-Triggered Pipelines (Next)

Pipeline configs have a `timer` field (cron spec string, e.g. `"0 0 22 ? * MON-FRI"`) and `timer_only_on_changes` flag but nothing evaluates them.

### 1. Schema Update
Add `timer_only_on_changes` boolean field to `pipelines` table (the `timer` string field already exists).

### 2. `ExGoCD.Materials.TimerScheduler` GenServer
- On startup, read all pipelines with a non-nil `timer` field.
- Parse the cron spec and register a recurring `:schedule` timer for each.
- On each tick: if `timer_only_on_changes == true`, skip if no new material revisions since last run; otherwise call `Pipelines.trigger_pipeline/1` with trigger cause `"timer"`.
- Re-register timers when pipeline config changes (subscribe to `"pipelines:updates"` PubSub).

### 3. Trigger Flow Integration
`trigger_pipeline/1` already handles the full flow. Timer calls it with no extra changes needed except recording the build cause as `"Timer"` in `PipelineInstance.build_cause`.

### 4. Tests
- Given a pipeline with `timer: "* * * * *"` and `timer_only_on_changes: false`, after one cron tick, a new `PipelineInstance` exists.
- Given `timer_only_on_changes: true` and no new modifications since last run, no new instance is created.
- Given `timer_only_on_changes: true` and a new modification, instance is created.

---

## Phase 5: Manual Stage Gate

`approval_type: "manual"` is stored and validated on `Stage` but `trigger_next_stage` currently advances to the next stage automatically regardless of its approval type.

### 1. Gate in `trigger_next_stage`
In `do_complete_stage → maybe_trigger_next_stage → trigger_next_stage`: check if `next_stage.approval_type == "manual"`. If so, create the `StageInstance` in state `"Awaiting"` (not `"Building"`) and do NOT schedule any job instances yet.

### 2. `Pipelines.approve_stage/3`
```
approve_stage(pipeline_name, pipeline_counter, stage_name) :: {:ok, stage_instance} | {:error, reason}
```
- Finds the awaiting `StageInstance`.
- Transitions it from `"Awaiting"` → `"Building"`.
- Schedules its `JobInstance`s into the `Scheduler`.
- Broadcasts `pipelines:updates`.

### 3. API / LiveView
- REST endpoint: `POST /go/pipelines/:pipeline_name/:counter/:stage_name/run` (mirrors GoCD API v1).
- Dashboard LiveView: show a "▶ Approve" button on awaiting stages for users with operate permission.

### 4. Tests
- Given a pipeline with stage1 (auto) → stage2 (manual): after stage1 passes, stage2 `StageInstance` exists in state `"Awaiting"` with no scheduled jobs.
- Calling `approve_stage/3` transitions stage2 to `"Building"` and enqueues jobs.
- Calling `trigger_pipeline` while stage2 is awaiting returns `{:error, :pipeline_locked}` for `lockOnFailure` pipelines (pipeline is still considered "active").
