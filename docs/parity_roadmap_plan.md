# GoCD Parity Implementation Roadmap

This document outlines the design and implementation steps for completing the missing GoCD parity features in the **ex_gocd** rewrite.

---

## Phase 1: SCM Polling & Modification Engine (Target)

To support automatic pipeline triggering, the server must query VCS repositories periodically and store commits in the database.

### 1. Database Schema
Create a `modifications` table to track SCM changes:
*   `id` (PK)
*   `material_id` (FK to materials)
*   `revision` (String - commit SHA or revision string)
*   `committer_name` (String)
*   `committer_email` (String)
*   `comment` (Text)
*   `modified_time` (DateTime)

### 2. SCM Polling Service (`ExGoCD.Materials.Poller`)
Implement a GenServer that:
*   Queries active materials on startup.
*   Triggers background check jobs periodically (e.g. every 60 seconds).
*   Uses a locking mechanism (or single process per material) to avoid concurrent poll operations on the same repo.
*   Executes local shell commands (e.g. `git ls-remote` and `git log`) to extract the latest revisions.

### 3. Pipeline Trigger Hooks
*   When a new revision is detected:
    1.  Save the modification to the database.
    2.  Find all pipelines using the material.
    3.  Compute build causes and trigger the first stage of matching pipelines.

---

## Phase 2: Fan-In Resolution & Value Stream Mapping

Enforcing revision consistency across pipeline dependencies.

### 1. Pipeline Material Revisions (PMR) Schema
Create a join table `pipeline_material_revisions`:
*   `pipeline_instance_id` (FK to pipeline instances)
*   `material_id` (FK to materials)
*   `modification_id` (FK to modifications, optional)
*   `parent_pipeline_instance_id` (FK to upstream pipeline instances, optional)

### 2. Fan-In Backtracking Algorithm
*   Implement dependency graph resolution.
*   When triggering a downstream pipeline with multiple upstream parents, backtrack the DAG to locate the latest revision of a shared SCM material built by all parents.
*   Prevent triggering if parents are built with mismatched SCM versions.

---

## Phase 3: Advanced Scheduling & Concurrency Locks

Improving job queues and pipeline triggers.

### 1. Environment and Resource Matching
*   Update `ExGoCD.Scheduler` to validate:
    *   **Environments**: If a pipeline belongs to environment A, its jobs can only run on agents assigned to environment A.
    *   **Resources**: Agents must have all resource tags required by the job config.

### 2. Concurrency Locks
*   Add `lock_behavior` checks during trigger. If `lock_behavior` is `lockOnFailure` or `unlockWhenFinished`, verify if an active pipeline instance is already building. If yes, hold subsequent triggers in the queue.
