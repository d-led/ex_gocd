# Elixir/Phoenix → GoCD Source Module Mapping

This document maps **ex_gocd** (Phoenix/Elixir) modules and files to the **original GoCD** (Java) source. Paths under "GoCD source" are relative to the `gocd/` repository root. Use this when implementing a feature to find the canonical behavior and data model in the legacy codebase.

See also: [status.md](./status.md) (high-level module tables), [rewrite.md](./rewrite.md) (plan and protocol compatibility).

---

## 1. Domain & config (schemas and context)

| Phoenix module / file | GoCD source (main) | Notes |
| --------------------- | ------------------ | ----- |
| `ExGoCD.Pipelines` | `server/.../BuildAssignmentService.java`, `server/.../ScheduleService.java` | Pipeline listing, trigger, dashboard data |
| `ExGoCD.Pipelines.Pipeline` (schema) | `config/config-api/.../PipelineConfig.java` | Pipeline **config** (name, group, label_template, stages, materials) |
| `ExGoCD.Pipelines.PipelineInstance` (schema) | `domain/.../Pipeline.java` | Pipeline **instance** (counter, label, buildCause, stages) |
| `ExGoCD.Pipelines.Stage` (schema) | `config/config-api/.../StageConfig.java` | Stage **config** (name, approval_type, jobs) |
| `ExGoCD.Pipelines.StageInstance` (schema) | `domain/.../Stage.java` | Stage **instance** (counter, state, result, job_instances) |
| `ExGoCD.Pipelines.Job` (schema) | `config/config-api/.../JobConfig.java` | Job **config** (name, tasks, resources, timeout) |
| `ExGoCD.Pipelines.JobInstance` (schema) | `domain/.../JobInstance.java` | Job **instance** (state, result, agent_uuid, transitions) |
| `ExGoCD.Pipelines.Task` (schema) | `config/config-api/.../domain/Task.java`, `.../ExecTask.java` | Task interface + ExecTask; also AntTask, RakeTask in config-api |
| `ExGoCD.Pipelines.Material` (schema) | `config/config-api/.../materials/MaterialConfig.java` (+ GitMaterialConfig, etc.) | Material config (polymorphic by type) |
| `ExGoCD.Agents` | `server/.../AgentService.java` | Agent CRUD, status, bulk update |
| `ExGoCD.Agents.Agent` (schema) | `config/config-api/.../Agent.java` (config) + `common/.../AgentInstance.java` (runtime) | DB agent row; runtime state in AgentInstance |
| `ExGoCD.AgentJobRuns`, `ExGoCD.AgentJobRuns.AgentJobRun` | `server/.../JobInstanceService.java`, job execution tracking | Build run linked to JobInstance; console/artifact handling |
| `ExGoCD.Repo` | `db/`, `db-support/` | Ecto vs GoCD DB layer |
| (config server) | `config/config-server/.../ConfigRepository.java`, `MagicalGoConfigXmlLoader.java` | XML config load/save; we use DB + optional future GenServer |

---

## 2. Scheduling and agent communication

| Phoenix module / file | GoCD source (main) | Notes |
| --------------------- | ------------------ | ----- |
| `ExGoCD.Scheduler` | `server/.../BuildAssignmentService.java`, `server/.../messaging/scheduling/WorkFinder.java` | Job queue; assign work on idle agent (we use WebSocket ping → try_assign_work) |
| `ExGoCDWeb.AgentChannel` | `server/.../remote/BuildRepositoryRemoteImpl.java` (get_work, report_*), WebSocket protocol | Agent WebSocket: ping, build, reportCurrentStatus, reportCompleted, cancelBuild |
| `ExGoCDWeb.AgentSocket` | Agent remoting endpoint | Our `/agent-websocket` vs legacy HTTP remoting |
| `ExGoCDWeb.AdminAgentController` | `server/.../controller/AgentRegistrationController.java` | Agent registration (form POST, token flow) |
| `ExGoCD.AgentRegistry` | In-memory registry of connected agents (channel pids) | GoCD uses DB + lastHeardTime; we have live channel + mark_lost_contact on terminate |
| `ExGoCDWeb.AgentPresence` | Presence for UI (who is connected) | Optional; GoCD doesn’t have same presence concept |
| `ExGoCDWeb.AgentSerializer` | Agent protocol JSON (build payload, etc.) | Match [gocd-golang-agent](https://github.com/gocd-contrib/gocd-golang-agent) protocol |

---

## 3. HTTP API and Web

| Phoenix module / file | GoCD source (main) | Notes |
| --------------------- | ------------------ | ----- |
| `ExGoCDWeb.API.AgentController` | `api/api-agents-v7/.../AgentsControllerV7.java` | REST agents API (list, get, bulk update, etc.) |
| `ExGoCDWeb.API.AgentJSON` | `api/api-agents-v7/.../representers/AgentRepresenter.java`, `AgentsRepresenter.java` | JSON shape per [api.go.cd](https://api.gocd.org/current/#agents) |
| `ExGoCDWeb.API.JobController` | `api/api-job-instance-v1/.../JobInstanceControllerV1.java` | Job instance API (status, history) |
| `ExGoCDWeb.API.BuildConsoleController` | Console log upload/download in server | POST console log, GET job console output |
| `ExGoCDWeb.API.BuildConsoleJSON` | Console representation | |
| Dashboard data (from `Pipelines.list_for_dashboard`) | `api/api-dashboard-v4/.../DashboardControllerV4.java`, `DashboardFor.java`, representers | Pipeline groups, instances, stage status for UI |
| `ExGoCDWeb.Router` | `spark/spark-base/.../Routes.java` | Route definitions; we use latest API version only |

---

## 4. LiveView (UI) → GoCD webapp

| Phoenix LiveView / component | GoCD source (main) | Notes |
| --------------------------- | ------------------ | ----- |
| `ExGoCDWeb.DashboardLive` | `server/.../webpack/views/dashboard/` (TSX), dashboard API above | Pipeline groups, instances, stages, play button |
| `ExGoCDWeb.AgentsLive` | `server/.../webpack/views/pages/agents/` | Agents table, tabs, bulk operations |
| `ExGoCDWeb.AgentJobHistoryLive` | `server/.../webpack/views/pages/agent-job-run-history/` | Job run history for an agent |
| `ExGoCDWeb.AgentJobRunDetailLive` | Job detail / console view in server | Console log, cancel, result |
| `ExGoCDWeb.MaterialsLive` | `server/.../webpack/views/pages/materials/` (or similar) | Placeholder → materials UI |
| `ExGoCDWeb.AdminLive` | Admin area in server | Placeholder → admin UI |
| `ExGoCDWeb.Layouts` (e.g. `site_header`) | `server/.../webpack/views/` (site_header, menu) | Header, nav, GoCD CSS |

---

## 5. Supporting and infrastructure

| Phoenix module / file | GoCD source (main) | Notes |
| --------------------- | ------------------ | ----- |
| `ExGoCD.Policies`, `ExGoCD.Policies.AgentPolicy` | Authorization in API layer | Permissions for agents, pipelines, etc. |
| `ExGoCD.Accounts`, `ExGoCD.Accounts.User` | User/auth in server | Authn/authz; we may keep minimal initially |
| `ExGoCD.MockData` | Test fixtures, Mother classes | e.g. `PipelineConfigMother`, `JobInstanceMother` in config-api/domain testFixtures |
| `ExGoCD.Application` | `server/.../initializers/ApplicationInitializer.java` | Startup; we start Scheduler, PubSub, etc. |
| `test/support/fixtures.ex` | `*Mother.java`, test helpers | Fixtures for tests |

---

## 6. Key GoCD paths quick reference (gocd repo)

- **Config (definitions):** `config/config-api/src/main/java/com/thoughtworks/go/config/` — PipelineConfig, StageConfig, JobConfig, Agent; `.../domain/Task.java`, `.../config/ExecTask.java`; `.../materials/MaterialConfig.java`.
- **Domain (execution instances):** `domain/src/main/java/com/thoughtworks/go/domain/` — Pipeline.java, Stage.java, JobInstance.java.
- **Agent runtime:** `common/src/main/java/com/thoughtworks/go/domain/AgentInstance.java`; `common/.../AgentInstances.java`.
- **Server services:** `server/src/main/java/com/thoughtworks/go/server/service/` — AgentService, BuildAssignmentService, ScheduleService, JobInstanceService; `server/.../messaging/scheduling/WorkFinder.java`.
- **Agent registration:** `server/.../controller/AgentRegistrationController.java`.
- **Remoting (work assignment):** `server/.../remote/BuildRepositoryRemoteImpl.java`.
- **REST API:** `api/api-agents-v7/.../AgentsControllerV7.java`; `api/api-dashboard-v4/.../DashboardControllerV4.java`; `api/api-job-instance-v1/.../JobInstanceControllerV1.java`.
- **UI:** `server/src/main/webapp/WEB-INF/rails/webpack/views/` — dashboard/, pages/agents/, pages/agent-job-run-history/.

---

## 7. Not mapped / deferred

- **Plugins:** `plugin-infra/go-plugin-*` — deferred; external tools via exec for now.
- **Config server XML:** Full `config/config-server` (MagicalGoConfigXmlLoader, serialization) — we use DB-backed config; XML import/export can be added later.
- **Elastic agents:** `ElasticAgentPluginService`, `ElasticAgentRequestProcessor*` — deferred.
- **Value Stream Map, CCTray, etc.:** Their controllers and domain — add when implementing those features.

Use this mapping to keep the rewrite aligned with the legacy GoCD behavior and domain language while implementing new features or fixing bugs.
