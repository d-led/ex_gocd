# GoCD Parity Blind Spots & Testing Gaps

This document compiles an inventory of functional and testing blind spots in the **ex_gocd** Phoenix rewrite compared to the legacy GoCD Java test suite specifications. It details what features are present and tested in the legacy Java codebase but currently missing, faked, or simplified in the rewrite.

---

## 1. SCM & Materials Processing

Original GoCD has a robust polling and dependency resolution engine. In `ex_gocd`, materials are defined in schemas, but the core processing and triggering logic remains largely unimplemented or faked.

### A. Fan-in Dependency Resolution
*   **Legacy Behavior (`FaninDependencyResolutionTest.java`)**:
    When pipelines form complex graph topologies (e.g., diamond or triangle dependencies on SCM materials), GoCD guarantees that a downstream pipeline (like `staging`) only triggers when all upstream pipelines (like `acceptance` and `regression`) have built using the **exact same SCM revision**. If an upstream pipeline fails to build the latest revision, GoCD backtracks to locate and run on the last mutually compatible SCM revision across the dependency graph.
*   **Rewrite Gap**:
    No fan-in resolution algorithm exists. Triggering is done manually (via the Play button) or sequentially without verification of revision consistency. This can lead to mismatched builds if upstream stages fail.
*   **Testing Gap**:
    We lack integration tests that verify graph-based build cause calculations or backtracking when upstream parents fail.

### B. Multi-SCM & Material Types
*   **Legacy Behavior (`MaterialConfigsTest.java`, SCM material updates)**:
    GoCD supports Git, Subversion (SVN), Mercurial (Hg), Perforce (P4), TFS, dependency materials, package materials (NuGet/Yum/APT), and pluggable custom SCMs. Legacy tests cover credential masking, URL parsing/validation (e.g., `HgUrlArgumentTest.java`), SSH configuration, and git-submodule checking.
*   **Rewrite Gap**:
    Only Git is supported at a schema level; other SCM types are ignored. Submodule recursion, shallow clone policies, and credential sanitization are not implemented or tested.
*   **Testing Gap**:
    No tests exist for SCM credential parsing, SSH keys handling, or checking revision modifications.

### C. Polling Scheduler vs. Post-Commit Hooks
*   **Legacy Behavior (`MaterialUpdateServiceTest.java`, `GitPostCommitHookImplementerTest.java`)**:
    GoCD schedules recurring background polling of repositories (using exponential backoff on network failures) and exposes API hooks for instant trigger via post-commit webhooks from GitHub, GitLab, and Bitbucket.
*   **Rewrite Gap**:
    No polling GenServer or background check mechanism exists. Webhook endpoint handlers (`/api/materials/notify` or webhooks) are completely absent.
*   **Testing Gap**:
    No tests exist for webhook handling, material polling, or polling throttling policies.

---

## 2. Configuration Validation & Schema Upgrades

GoCD is driven by `cruise-config.xml`. While `ex_gocd` uses a database-backed schema, it bypasses configuration sanity and validation checks.

### A. Pipeline Graph Cycle Detection
*   **Legacy Behavior (`DFSCycleDetectorTest.java`)**:
    During configuration saves or updates, GoCD performs topological sorting using a Depth-First Search (DFS) to detect circular dependencies between pipelines (e.g., `A -> B -> C -> A`) and throws a validation exception if a cycle is found. It also validates that dependency materials refer to existing pipelines and stages.
*   **Rewrite Gap**:
    No cycle detection algorithm is implemented. A user can define circular pipeline configurations in the database, causing infinite loops during execution triggers.
*   **Testing Gap**:
    We have no tests verifying configuration validation for DAG loops or broken stage references.

### B. Configuration Templates & Parameterization
*   **Legacy Behavior (`TemplateExpansionPreprocessorTest.java`, `ParamConfigTest.java`)**:
    GoCD supports pipeline templates where pipelines inherit stages/jobs and overwrite parameters defined as `#{parameter_name}`. This allows reusability. Legacy tests verify parameter scoping, interpolation, and template validation.
*   **Rewrite Gap**:
    No templates schema, preprocessors, or parameter interpolation engines exist. All pipelines must define their schemas and jobs directly in their DB entries.
*   **Testing Gap**:
    We lack tests asserting parameter resolution or template inheritance.

### C. Config Repos / Pipeline-as-Code
*   **Legacy Behavior (`GoConfigRepoConfigDataSourceTest.java`, `ConfigRepoPluginTest.java`)**:
    Allows users to define pipelines in external JSON/YAML files in git repositories (Config Repos). The server parses these dynamically and merges them with local configurations.
*   **Rewrite Gap**:
    No configuration repository sync or parsing engine is implemented. All configuration changes must be made via database migrations or direct DB inserts.

---

## 3. Advanced Scheduling & Agent Matching

Scheduling in `ex_gocd` is handled by a simple in-memory queue. In contrast, GoCD implements a multi-stage workflow engine.

### A. Resource and Environment Matching
*   **Legacy Behavior (`JobAssignmentIntegrationTest.java`)**:
    Jobs are matched to agents based on matching resource tags (e.g., `jdk17`, `docker`) and environments (e.g., `staging`, `production`). An agent assigned to the `production` environment can only pick up jobs from pipelines belonging to the `production` environment.
*   **Rewrite Gap**:
    Agent assignments are done without resource or environment checks. Any idle agent picking up a task will be assigned the job, which can cause security issues and build failures.
*   **Testing Gap**:
    No tests exist checking that an agent is rejected from a build if it lacks required resources or belongs to a different environment.

### B. Run-on-All-Agents & Run-Multiple-Instance Jobs
*   **Legacy Behavior (`RunMultipleInstanceJobTypeConfigTest.java`)**:
    GoCD supports scheduling a job on all active agents (e.g., to run cleanups or daemon tasks) or scheduling multiple instances of a job (e.g., for test parallelization).
*   **Rewrite Gap**:
    Only standard 1-to-1 job to agent scheduling is implemented.
*   **Testing Gap**:
    No tests exist checking job multiplexing or daemon job runs.

### C. Pipeline Locking & Unlock Policies
*   **Legacy Behavior (`PipelinePauseServiceIntegrationTest.java`, `PipelineUnlockApiServiceTest.java`)**:
    GoCD pipelines can be configured as "locked", which prevents concurrent runs. If a pipeline is locked, subsequent instances wait in queue until the active one completes, unless manually unlocked.
*   **Rewrite Gap**:
    No lock flags or concurrent build prevention checks exist. Multiple pipeline counters can build concurrently.
*   **Testing Gap**:
    No tests exist checking concurrency locks, stage lock checks, or unlock API calls.

---

## 4. Security, Roles, and Authentication

GoCD has a complex security sub-system supporting external directories and custom permissions.

### A. External Auth Plugins & Access Tokens
*   **Legacy Behavior (`TokenServiceTest.java`, LDAP/OAuth integrations)**:
    Supports integrating with external identity providers (LDAP, AD, GitHub OAuth) and managing personal access tokens for API requests.
*   **Rewrite Gap**:
    No directory integration, OAuth flow, or access token schemas/verification are present.
*   **Testing Gap**:
    We do not test authentication plugins or API token validations.

### B. Granular Role-Based Access Control (RBAC)
*   **Legacy Behavior (`GoConfigPipelinePermissionsAuthorityTest.java`)**:
    Granular permissions (View, Operate, Admin) can be assigned to users or roles at the pipeline group and environment levels.
*   **Rewrite Gap**:
    We have a basic "visitor guest is admin" fallback mode, but we do not support defining custom roles or restricting specific pipeline groups to certain users.
*   **Testing Gap**:
    We lack tests checking access denial when a non-authorized user attempts to trigger, pause, or view a pipeline.

---

## 5. Console Logging, Health Monitoring, & Artifacts

Managing logs and artifacts safely is essential for large CD systems.

### A. Console Inactivity & Build Hang Detection
*   **Legacy Behavior (`ConsoleActivityMonitorTest.java`)**:
    GoCD tracks active job writes. If an agent does not stream any console output for a configured timeout, the server automatically issues a cancel command to the agent to terminate the hung process.
*   **Rewrite Gap**:
    No build hang detection or timeout monitors exist. Hung agent builds run indefinitely until the process is manually killed.
*   **Testing Gap**:
    No tests assert automatic build cancellation on stream silence.

### B. Disk Space Monitors & Auto-Cleanup Policies
*   **Legacy Behavior (`GoDiskSpaceMonitorTest.java`, `ArtifactsDiskSpaceFullCheckerTest.java`)**:
    GoCD monitors database and artifact directory disk space. If disk space falls below critical thresholds, it halts pipeline scheduling, pauses notifications, and triggers auto-purges of old artifacts.
*   **Rewrite Gap**:
    No disk monitoring or auto-purging logic is implemented.
*   **Testing Gap**:
    No tests cover low disk space failures or artifact cleanups.

### C. Artifact Checksums & Fetch Artifact Task
*   **Legacy Behavior (`ArtifactMd5ChecksumsTest.java`, `FetchTaskTest.java`)**:
    When artifacts are uploaded, GoCD calculates MD5/SHA checksums and writes them to a manifest file. Downstream jobs run `FetchArtifact` tasks that download these files, verifying checksums to prevent corruption or security tampering.
*   **Rewrite Gap**:
    No checksum verification is performed. Downstream fetch tasks are not supported.
*   **Testing Gap**:
    No integration tests assert artifact verification or task download security.
