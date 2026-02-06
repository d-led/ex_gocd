# GoCD Rewrite Status

## Overview

This document tracks the incremental Phoenix rewrite of [GoCD](https://www.gocd.org/). The tables below map the original Java/Gradle modules to their Phoenix/Elixir equivalents.

Legend:

- ❌ Not started
- 🚧 In progress
- Complete
- 🔄 Partial / Under review
- 🚫 Not applicable (infrastructure/build files)

---

## Module Mapping

### Core Server Modules

| GoCD Module                         | Purpose                 | Status | Phoenix Equivalent                  | Notes                              |
| ----------------------------------- | ----------------------- | ------ | ----------------------------------- | ---------------------------------- |
| `server/`                           | Main server application | ❌     | `lib/ex_gocd/`                      | Core domain logic, services        |
| `domain/`                           | Domain models           | 🚧     | `lib/ex_gocd/pipelines/`            | Pipelines, Stages, Jobs, Materials |
| `common/`                           | Shared utilities        | ❌     | `lib/ex_gocd/`                      | Shared utilities across modules    |
| `config/config-api/`                | Configuration API       | 🚧     | `lib/ex_gocd/pipelines/`            | Config parsing, validation         |
| `config/config-server/`             | Configuration server    | ❌     | `lib/ex_gocd/config/server.ex`      | Config management GenServer        |
| `db/`                               | Database models         | ❌     | `lib/ex_gocd/repo.ex`, `priv/repo/` | Ecto schemas and migrations        |
| `db-support/db-support-base/`       | DB abstraction          | 🚫     | N/A                                 | Ecto handles this                  |
| `db-support/db-support-postgresql/` | PostgreSQL support      | ❌     | `config/runtime.exs`                | Ecto adapter config                |
| `db-support/db-support-h2/`         | H2 DB (in-memory)       | ❌     | SQLite adapter                      | For dev/test                       |
| `db-support/db-support-mysql/`      | MySQL support           | 🚫     | N/A                                 | Focus on PostgreSQL/SQLite         |
| `db-support/db-migration/`          | DB migrations           | ❌     | `priv/repo/migrations/`             | Ecto migrations                    |
| `base/`                             | Base classes            | 🚫     | N/A                                 | OOP pattern, not needed            |
| `util/`                             | Utility classes         | ❌     | `lib/ex_gocd/utils/`                | General utilities                  |

### API Modules

| GoCD Module                   | Purpose            | Status | Phoenix Equivalent                                          | Notes                  |
| ----------------------------- | ------------------ | ------ | ----------------------------------------------------------- | ---------------------- |
| `api/api-base/`               | API base           | ❌     | `lib/ex_gocd_web/controllers/`                              | Phoenix controllers    |
| `api/api-dashboard-v4/`       | Dashboard API      | ❌     | `lib/ex_gocd_web/live/dashboard_live.ex`                    | LiveView               |
| `api/api-pipeline-*`          | Pipeline APIs      | ❌     | `lib/ex_gocd_web/controllers/api/pipeline_controller.ex`    | REST API               |
| `api/api-agents-v7/`          | Agents API         | ❌     | `lib/ex_gocd_web/controllers/api/agent_controller.ex`       | Agent management       |
| `api/api-materials-v2/`       | Materials API      | ❌     | `lib/ex_gocd_web/controllers/api/material_controller.ex`    | SCM materials          |
| `api/api-users-v3/`           | Users API          | ❌     | `lib/ex_gocd_web/controllers/api/user_controller.ex`        | User management        |
| `api/api-environments-v3/`    | Environments API   | ❌     | `lib/ex_gocd_web/controllers/api/environment_controller.ex` | Environment config     |
| `api/api-backup-config-v1/`   | Backup config      | ❌     | `lib/ex_gocd/backup/`                                       | Backup management      |
| `api/api-plugin-infos-v7/`    | Plugin info        | 🚫     | N/A                                                         | Plugin system deferred |
| `api/api-template-config-v7/` | Pipeline templates | ❌     | `lib/ex_gocd/config/template.ex`                            | Template support       |
| `api/api-stage-*`             | Stage APIs         | ❌     | `lib/ex_gocd_web/controllers/api/stage_controller.ex`       | Stage operations       |
| `api/api-job-instance-v1/`    | Job instance API   | ❌     | `lib/ex_gocd_web/controllers/api/job_controller.ex`         | Job management         |
| `api/api-version-v1/`         | Version API        | ❌     | `lib/ex_gocd_web/controllers/api/version_controller.ex`     | Version info           |

### Agent Modules

| GoCD Module               | Purpose            | Status | Phoenix Equivalent   | Notes                |
| ------------------------- | ------------------ | ------ | -------------------- | -------------------- |
| `agent/`                  | Main agent         | ❌     | Go binary (`agent/`) | Standalone Go agent  |
| `agent-common/`           | Agent common code  | ❌     | Go package           | Shared agent code    |
| `agent-launcher/`         | Agent launcher     | ❌     | Go binary            | Agent bootstrapping  |
| `agent-bootstrapper/`     | Agent bootstrapper | ❌     | Go binary            | Agent initialization |
| `agent-process-launcher/` | Process launcher   | ❌     | Go package           | Process management   |

### Web/UI Modules

| GoCD Module               | Purpose       | Status | Phoenix Equivalent            | Notes                       |
| ------------------------- | ------------- | ------ | ----------------------------- | --------------------------- |
| `server/src/main/webapp/` | Web assets    | ❌     | `assets/`, `lib/ex_gocd_web/` | Phoenix/LiveView UI         |
| `spark/spark-spa/`        | SPA framework | ❌     | LiveView                      | No SPA needed with LiveView |
| `spark/spark-base/`       | Web framework | 🚫     | N/A                           | Phoenix handles this        |

### Infrastructure Modules

| GoCD Module         | Purpose            | Status | Phoenix Equivalent | Notes                |
| ------------------- | ------------------ | ------ | ------------------ | -------------------- |
| `jetty/`            | Jetty server       | 🚫     | N/A                | Phoenix uses Cowboy  |
| `app-server/`       | Application server | 🚫     | N/A                | Phoenix handles this |
| `server-launcher/`  | Server launcher    | 🚫     | N/A                | `mix phx.server`     |
| `rack_hack/`        | Ruby Rack          | 🚫     | N/A                | Not needed           |
| `commandline/`      | CLI utilities      | ❌     | Mix tasks          | `mix gocd.*` tasks   |
| `jar-class-loader/` | JAR loading        | 🚫     | N/A                | Not applicable       |

### Plugin Infrastructure

| GoCD Module                | Purpose       | Status | Phoenix Equivalent | Notes              |
| -------------------------- | ------------- | ------ | ------------------ | ------------------ |
| `plugin-infra/go-plugin-*` | Plugin system | 🚫     | Future             | Deferred for later |

### Build/Test Infrastructure

| GoCD Module        | Purpose             | Status | Phoenix Equivalent           | Notes              |
| ------------------ | ------------------- | ------ | ---------------------------- | ------------------ |
| `buildSrc/`        | Build scripts       | 🚫     | N/A                          | Mix handles builds |
| `test/test-utils/` | Test utilities      | ❌     | `test/support/`              | Test helpers       |
| `test/test-agent/` | Agent test fixtures | ❌     | `test/support/agent_case.ex` | Agent testing      |
| `test/http-mocks/` | HTTP mocks          | ❌     | `test/support/`              | Use Bypass or Mox  |

### Installers/Docker

---

## Domain Model Mapping (GoCD Java → Phoenix Elixir)

### Configuration (Pipeline Definition)

| GoCD Java Class  | Location                                    | Phoenix Schema        | Location                            | Status | Notes                             |
| ---------------- | ------------------------------------------- | --------------------- | ----------------------------------- | ------ | --------------------------------- |
| `PipelineConfig` | `config/config-api/.../PipelineConfig.java` | `Pipeline`            | `lib/ex_gocd/pipelines/pipeline.ex` | 🚧     | Pipeline definition/configuration |
| `StageConfig`    | `config/config-api/.../StageConfig.java`    | `Stage`               | `lib/ex_gocd/pipelines/stage.ex`    | 🚧     | Stage definition within pipeline  |
| `JobConfig`      | `config/config-api/.../JobConfig.java`      | `Job`                 | `lib/ex_gocd/pipelines/job.ex`      | 🚧     | Job definition within stage       |
| `ExecTask`       | `config/config-api/.../ExecTask.java`       | `Task`                | `lib/ex_gocd/pipelines/task.ex`     | 🚧     | Task definition (exec/ant/rake)   |
| `AntTask`        | `config/config-api/.../AntTask.java`        | `Task` (type: "ant")  | `lib/ex_gocd/pipelines/task.ex`     | 🚧     | Ant build task                    |
| `RakeTask`       | `config/config-api/.../RakeTask.java`       | `Task` (type: "rake") | `lib/ex_gocd/pipelines/task.ex`     | 🚧     | Rake task                         |
| `MaterialConfig` | `config/config-api/.../materials/*.java`    | `Material`            | `lib/ex_gocd/pipelines/material.ex` | 🚧     | Material (Git/SVN/etc) config     |

### Execution Instances (Runtime Tracking)

| GoCD Java Class | Location                      | Phoenix Schema     | Location                                     | Status | Notes                                   |
| --------------- | ----------------------------- | ------------------ | -------------------------------------------- | ------ | --------------------------------------- |
| `Pipeline`      | `domain/.../Pipeline.java`    | `PipelineInstance` | `lib/ex_gocd/pipelines/pipeline_instance.ex` | 🚧     | Single pipeline execution (has counter) |
| `Stage`         | `domain/.../Stage.java`       | `StageInstance`    | `lib/ex_gocd/pipelines/stage_instance.ex`    | 🚧     | Single stage execution in pipeline run  |
| `JobInstance`   | `domain/.../JobInstance.java` | `JobInstance`      | `lib/ex_gocd/pipelines/job_instance.ex`      | 🚧     | Single job execution in stage run       |

### Key Field Mappings

#### Pipeline (domain/Pipeline.java) → ? (MIXED - needs split)

**GoCD Fields:**

- `pipelineName`: String
- `counter`: int - increments with each run
- `pipelineLabel`: PipelineLabel - display label (e.g., "1.2.3")
- `stages`: Stages - collection of Stage instances
- `buildCause`: BuildCause - what triggered this run
- `naturalOrder`: double - ordering for display

**Current Phoenix Schema Issues:**

- ❌ Currently `Pipeline` schema mixes Config + Instance concepts
- ❌ Missing: counter, label, buildCause, naturalOrder
- ❌ Wrong: has label_template (that's PipelineConfig)

**Required Split:**

1. `Pipeline` should be the CONFIG (PipelineConfig in GoCD)
   - name, group, label_template, lock_behavior, environment_variables, timer
   - has_many :stages (StageConfig)
   - many_to_many :materials

2. `PipelineInstance` should track EXECUTION (Pipeline in GoCD)
   - counter, label, status, triggered_by, trigger_message
   - scheduled_at, completed_at, natural_order
   - belongs_to :pipeline
   - has_many :stage_instances

#### Stage (domain/Stage.java) → ? (MIXED - needs split)

**GoCD Fields:**

- `pipelineId`: Long
- `name`: String
- `jobInstances`: JobInstances
- `approvedBy`: String
- `cancelledBy`: String
- `orderId`: int
- `createdTime`: Timestamp
- `lastTransitionedTime`: Timestamp
- `approvalType`: String
- `fetchMaterials`: boolean
- `result`: StageResult
- `counter`: int
- `identifier`: StageIdentifier
- `completedByTransitionId`: Long
- `state`: StageState
- `latestRun`: boolean
- `cleanWorkingDir`: boolean
- `rerunOfCounter`: Integer
- `artifactsDeleted`: boolean
- `configVersion`: String

**Current Phoenix Schema Issues:**

- ❌ Currently `Stage` schema mixes Config + Instance concepts
- ❌ Missing: orderId, createdTime, counter, state, result, latestRun, rerunOfCounter, completedByTransitionId

**Required Split:**

1. `Stage` should be the CONFIG (StageConfig in GoCD)
   - name, fetch_materials, clean_working_directory, never_cleanup_artifacts, approval_type
   - belongs_to :pipeline
   - has_many :jobs

2. `StageInstance` should track EXECUTION (Stage in GoCD)
   - counter, state, result, approved_by, cancelled_by, scheduled_at, completed_at
   - belongs_to :pipeline_instance
   - has_many :job_instances

#### JobInstance (domain/JobInstance.java) → JobInstance ✅ (mostly correct)

**GoCD Fields:**

- `stageId`: long
- `name`: String
- `state`: JobState (Scheduled/Assigned/Building/Completed/etc)
- `result`: JobResult (Unknown/Passed/Failed/Cancelled)
- `agentUuid`: String
- `stateTransitions`: JobStateTransitions (not persisted separately)
- `scheduledDate`: Date
- `ignored`: boolean
- `identifier`: JobIdentifier
- `runOnAllAgents`: boolean
- `runMultipleInstance`: boolean
- `originalJobId`: Long
- `rerun`: boolean
- `pipelineStillConfigured`: boolean
- `plan`: JobPlan

**Current Phoenix Schema Issues:**

- ❌ Missing: ignored, originalJobId, rerun
- ❌ JobConfig fields (resources, environment_variables, timeout, run_instance_count) are in WRONG schema
- ❌ Should reference a JobConfig, not duplicate config fields

**Required Split:**

1. `Job` should be the CONFIG (JobConfig in GoCD)
   - name, timeout, resources, environment_variables, run_instance_count, elastic_profile_id
   - belongs_to :stage
   - has_many :tasks

2. `JobInstance` should track EXECUTION (JobInstance in GoCD)
   - name, state, result, agent_uuid, scheduled_at, assigned_at, completed_at
   - run_on_all_agents, run_multiple_instance (flags from Job template)
   - original_job_id (for reruns), rerun (boolean), ignored
   - belongs_to :stage_instance
   - belongs_to :job (the config/definition)

#### Task Interface → Task Schema Issues

**GoCD Structure:**

- `Task` is an INTERFACE
- Implementations: `ExecTask`, `AntTask`, `RakeTask`, `NantTask`, `FetchTask`, etc.
- Each has different fields (ExecTask has command+args, AntTask has target+working_directory)

**Current Phoenix Schema Issues:**

- ✅ Using polymorphic `type` field is correct
- ❌ Task is stored with Job - but in GoCD Tasks belong to JobConfig, not JobInstance
- ❌ Tasks are executed as part of job run, but config is separate

**Required Approach:**

- `Task` schema is CONFIG (part of JobConfig)
- Task execution is tracked separately (not yet in GoCD codebase visible here)

#### Material (materials/Material.java interface) → Material

**GoCD Structure:**

- `Material` is an INTERFACE
- Implementations: GitMaterial, SvnMaterial, HgMaterial, P4Material, TfsMaterial, DependencyMaterial, PackageMaterial, PluggableSCMMaterial
- Each type has different config fields

**Current Phoenix Schema Issues:**

- ✅ Polymorphic approach is reasonable
- ❌ Missing many material-specific fields
- ❌ GoCD has MaterialInstance (separate from config)

---

## Schema Correction Plan

### Critical Issues Identified

1. **Config vs Instance Confusion**: Current schemas mix pipeline/stage/job DEFINITIONS with EXECUTION tracking
2. **Missing Fields**: Many GoCD fields not present in Phoenix schemas
3. **Wrong Relationships**: Some belongs_to/has_many relationships incorrect
4. **Task Storage**: Tasks should only be in Job config, not duplicated to instances

### Required Changes

1. **Keep separate**:
   - `Pipeline` (config) + `PipelineInstance` (execution)
   - `Stage` (config) + `StageInstance` (execution)
   - `Job` (config) + `JobInstance` (execution)
   - `Task` (config only - no instance)
   - `Material` (config only)

2. **Add fields** to match GoCD exactly (see field mappings above)

3. **Fix relationships**:
   - PipelineInstance.belongs_to :pipeline
   - StageInstance.belongs_to :pipeline_instance
   - StageInstance.belongs_to :stage (the config)
   - JobInstance.belongs_to :stage_instance
   - JobInstance.belongs_to :job (the config)

| GoCD Module           | Purpose       | Status | Phoenix Equivalent    | Notes                       |
| --------------------- | ------------- | ------ | --------------------- | --------------------------- |
| `docker/gocd-server/` | Server Docker | ❌     | `docker-gocd-server/` | Already exists in workspace |
| `docker/gocd-agent/`  | Agent Docker  | ❌     | TBD                   | Go agent Docker             |
| `installers/`         | OS installers | 🚫     | N/A                   | Use Docker/releases         |

---

## Test Coverage Mapping

### Domain Tests

| GoCD Test Module                         | Test Type | Status | Phoenix Test                            | Notes                 |
| ---------------------------------------- | --------- | ------ | --------------------------------------- | --------------------- |
| `domain/src/test/.../Pipeline*Test.java` | Unit      | ❌     | `test/ex_gocd/domain/pipeline_test.exs` | Pipeline domain logic |
| `domain/src/test/.../Stage*Test.java`    | Unit      | ❌     | `test/ex_gocd/domain/stage_test.exs`    | Stage domain logic    |
| `domain/src/test/.../Job*Test.java`      | Unit      | ❌     | `test/ex_gocd/domain/job_test.exs`      | Job domain logic      |
| `domain/src/test/.../Material*Test.java` | Unit      | ❌     | `test/ex_gocd/domain/material_test.exs` | Material domain logic |
| `domain/src/test/.../Agent*Test.java`    | Unit      | ❌     | `test/ex_gocd/domain/agent_test.exs`    | Agent domain logic    |

### Config Tests

| GoCD Test Module                               | Test Type   | Status | Phoenix Test                          | Notes                     |
| ---------------------------------------------- | ----------- | ------ | ------------------------------------- | ------------------------- |
| `config/config-api/src/test/.../*Test.java`    | Unit        | ❌     | `test/ex_gocd/config/*_test.exs`      | Config parsing/validation |
| `config/config-server/src/test/.../*Test.java` | Integration | ❌     | `test/ex_gocd/config/server_test.exs` | Config server behavior    |

### Server Tests

| GoCD Test Module                           | Test Type        | Status | Phoenix Test                        | Notes                     |
| ------------------------------------------ | ---------------- | ------ | ----------------------------------- | ------------------------- |
| `server/src/test/.../scheduler/*Test.java` | Unit             | ❌     | `test/ex_gocd/scheduler/*_test.exs` | Scheduler GenServer tests |
| `server/src/test/.../service/*Test.java`   | Unit/Integration | ❌     | `test/ex_gocd/services/*_test.exs`  | Service layer tests       |
| `server/src/test/.../database/*Test.java`  | Integration      | ❌     | `test/ex_gocd/repo_test.exs`        | Database integration      |

### API Tests

| GoCD Test Module                               | Test Type  | Status | Phoenix Test                                                    | Notes              |
| ---------------------------------------------- | ---------- | ------ | --------------------------------------------------------------- | ------------------ |
| `api/api-dashboard-v4/src/test/.../*Test.java` | Controller | ❌     | `test/ex_gocd_web/live/dashboard_live_test.exs`                 | LiveView tests     |
| `api/api-pipeline-*/src/test/.../*Test.java`   | Controller | ❌     | `test/ex_gocd_web/controllers/api/pipeline_controller_test.exs` | API endpoint tests |
| `api/api-agents-v7/src/test/.../*Test.java`    | Controller | ❌     | `test/ex_gocd_web/controllers/api/agent_controller_test.exs`    | Agent API tests    |

### Agent Tests

| GoCD Test Module                       | Test Type        | Status | Phoenix Test                 | Notes                      |
| -------------------------------------- | ---------------- | ------ | ---------------------------- | -------------------------- |
| `agent/src/test/.../*Test.java`        | Unit/Integration | ❌     | Go tests (`agent/*_test.go`) | Agent implementation in Go |
| `agent-common/src/test/.../*Test.java` | Unit             | ❌     | Go tests                     | Common agent code          |

### Integration/E2E Tests

| GoCD Test Type           | Status | Phoenix Test                                   | Notes                  |
| ------------------------ | ------ | ---------------------------------------------- | ---------------------- |
| Server-Agent integration | ❌     | `test/integration/agent_registration_test.exs` | Agent communication    |
| Pipeline execution E2E   | ❌     | `test/integration/pipeline_execution_test.exs` | Full pipeline flow     |
| Material polling         | ❌     | `test/integration/material_polling_test.exs`   | SCM polling behavior   |
| Config reload            | ❌     | `test/integration/config_reload_test.exs`      | Dynamic config changes |

---

## Progress Metrics

- **Total GoCD Modules**: ~80+
- **Modules Started**: 0
- **Modules Complete**: 0
- **Modules Not Applicable**: ~15 (build/infra)

## Progress Log

- Created Phoenix LiveView project
- Replaced default view with GoCD-styled start page
- Created DashboardLive with GoCD layout & styling
- Implemented GoCD site header (dark #000728 background, navigation)
- Copied & adapted core GoCD CSS (site_header, variables, theme, dropdown)
- Added Open Sans font (Google Fonts)
- Built custom accessible dropdown component matching GoCD design
- Added comprehensive accessibility: ARIA roles, keyboard nav, screen reader support, skip links
- Mobile-first responsive: 44px touch targets, adaptive layouts
- Router configured for DashboardLive at / and /pipelines
- Docker Compose setup for development
- Fixed navigation menu items to match GoCD exactly (Dashboard, Agents, Materials, Admin)
- Fixed purple active indicator positioning (4px bar at bottom using ::after pseudo-element)
- Fixed font weight and text-transform (600 weight, uppercase)
- Removed duplicate border-bottom styling conflict
- Created comprehensive GoCD testing analysis document
- Created prioritization plan for incremental development
- Fixed navbar spacing to match GoCD pixel-perfectly (logo margins, nav item padding)
- Removed "Anonymous" user display to match GoCD unauthenticated state
- Updated rewrite.md with comprehensive design and styling approach documentation
- **Phase 1.3 Complete**: Created comprehensive test foundation (38 tests, all passing)
- Created DashboardLive tests (mount, render, events, accessibility)
- Created Layout component tests (header, navigation, responsive design)
- Created test fixtures module following GoCD's "Mother" pattern
- **Phase 1.2 Complete**: Recreated GoCD dashboard pixel-perfectly from source
- Created ExGoCD.MockData module with 8 realistic pipelines across 4 groups
- Completely rewrote dashboard HTML structure to match GoCD exactly:
  - pipeline_header with pipeline_sub_header (name + actions)
  - pipeline_operations with play/pause/play_with_options buttons
  - pipeline_instances with full instance details
  - pipeline_instance with more_info (Compare, Changes, VSM links)
  - pipeline_instance-details (triggered_by, timestamp)
  - pipeline_stages with pipeline_stage_manual_gate_wrapper
  - Exact pipeline_stage elements (34px × 16px colored blocks)
- Added complete CSS from GoCD source (pipeline_btn, pipeline_operations, more_info, etc.)
- Integrated mock data with triggered_by, counter, and all pipeline fields
- Added PostgreSQL 15 service to GitHub Actions workflow
- All 38 tests passing with updated assertions for new structure

---

## Next Steps

1. **Immediate (Phase 1.2 - Visual Verification)**:
   - Compare visual output at localhost:4000 vs http://localhost:8153/go/pipelines
   - Add sprite images or icon fonts for pipeline operation buttons
   - Fine-tune spacing and typography to match GoCD exactly

2. **Phase 2: Core Domain Model**:

3. **Phase 2: Core Domain Model**:
   - Define Ecto schemas for core domain (Pipeline, Stage, Job, Material, Agent)
   - Setup ExMachina for test fixtures
   - Write comprehensive schema tests

4. **Phase 3: Dashboard with Real Data**:
   - Implement context modules
   - Connect LiveView to database
   - Add seed data

5. **Later Phases**:
   - Implement basic config parsing
   - Create agent registration GenServer
   - Build material polling system
   - Implement pipeline scheduler
   - Develop agent (Go) with basic communication protocol

---

## Test Mapping (GoCD Java Tests → Phoenix Elixir Tests)

This section maps GoCD's Java test files to our corresponding Elixir test files, ensuring test coverage alignment with the source.

### Domain Model Tests (Instance/Execution Tracking)

| GoCD Test File         | Location                                   | Phoenix Test File            | Location                                            | Status | Key Test Patterns                                         |
| ---------------------- | ------------------------------------------ | ---------------------------- | --------------------------------------------------- | ------ | --------------------------------------------------------- |
| `JobInstanceTest.java` | `domain/src/test/.../JobInstanceTest.java` | `job_instance_test.exs`      | `test/ex_gocd/pipelines/job_instance_test.exs`      | ✅     | State transitions, timing, agent assignment               |
| `StageTest.java`       | `domain/src/test/.../StageTest.java`       | `stage_instance_test.exs`    | `test/ex_gocd/pipelines/stage_instance_test.exs`    | ✅     | State calculation, result aggregation, counter validation |
| `PipelineTest.java`    | `domain/src/test/.../PipelineTest.java`    | `pipeline_instance_test.exs` | `test/ex_gocd/pipelines/pipeline_instance_test.exs` | ✅     | BuildCause tracking, natural ordering, label generation   |

### Configuration Model Tests (Pipeline Definition)

| GoCD Test File                      | Location                                                 | Phoenix Test File   | Location                                   | Status | Key Test Patterns                                         |
| ----------------------------------- | -------------------------------------------------------- | ------------------- | ------------------------------------------ | ------ | --------------------------------------------------------- |
| `PipelineConfigTest.java`           | `config/config-api/src/test/.../PipelineConfigTest.java` | `pipeline_test.exs` | `test/ex_gocd/pipelines/pipeline_test.exs` | ✅     | Config validation, template handling, params              |
| `StageConfigTest.java`              | `config/config-api/src/test/.../StageConfigTest.java`    | `stage_test.exs`    | `test/ex_gocd/pipelines/stage_test.exs`    | ✅     | Approval types, fetch materials, cleanup artifacts        |
| `JobConfigTest.java`                | `config/config-api/src/test/.../JobConfigTest.java`      | `job_test.exs`      | `test/ex_gocd/pipelines/job_test.exs`      | ✅     | Timeout validation, resource allocation, elastic profiles |
| `TaskTest.java` (various)           | `config/config-api/src/test/.../tasks/*Test.java`        | `task_test.exs`     | `test/ex_gocd/pipelines/task_test.exs`     | ✅     | Task polymorphism, command validation                     |
| `MaterialConfigTest.java` (various) | `config/config-api/src/test/.../materials/*Test.java`    | `material_test.exs` | `test/ex_gocd/pipelines/material_test.exs` | ✅     | Material types, auto-update, filters                      |

### Key Test Insights from GoCD Source

1. **JobInstance Construction**:
   - Only requires `name` in constructor
   - `scheduledDate` set automatically via `schedule()` method
   - `job_id` (link to JobConfig) is optional, set later
   - State transitions tracked via `JobStateTransitions`

2. **Stage Construction**:
   - Requires: `name`, `jobInstances`, `approvedBy`, `cancelledBy`, `approvalType`
   - `createdTime` set automatically in constructor
   - `result` NOT required initially - calculated from job results later
   - State derived from job states

3. **Pipeline Construction**:
   - Requires: `buildCause` (what triggered run), `naturalOrder`
   - `counter` increments per pipeline run
   - Stages are added after construction

4. **Test Patterns Used by GoCD**:
   - "Mother" classes (e.g., `JobInstanceMother`, `StageMother`) for fixture creation
   - Separation of config tests vs instance tests
   - Focus on state transitions and calculation logic
   - Extensive use of mock TimeProvider for deterministic timing

### Test Coverage Alignment

**Current Status**: ✅ All core schema tests passing (97 tests, 0 failures)

**Alignment with GoCD**:

- ✅ Required fields match GoCD constructors
- ✅ Validation rules match GoCD constraints
- ✅ State/result enums match exactly
- ✅ Unique constraints match domain logic
- ✅ Defaults match GoCD behavior

**Test Fixtures**:

- Following GoCD's "Mother" pattern in `test/support/fixtures.ex`
- Building from minimal required fields (like GoCD constructors)
- State changes applied separately (not in constructor)

---

## Notes

- **Plugin System**: Deferred to later phase. Initial focus on core CD functionality
- **SCM Support**: Git only initially, can add others later
- **Database**: PostgreSQL primary, SQLite for dev/test
- **UI Framework**: DaisyUI with Phoenix LiveView (no React/SPA needed)
- **Agent**: Standalone Go binary, statically linked, no cgo
- **Telemetry**: Phoenix Telemetry for observability from day one
- **Testing**: Following GoCD's test pyramid - many unit tests, some integration, few E2E
