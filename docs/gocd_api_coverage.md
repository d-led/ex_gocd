# GoCD API Compatibility & Coverage Status

This document tracks the API compatibility and coverage status of the **ex_gocd** Phoenix rewrite relative to the official [GoCD REST API Spec](../../api.go.cd/source/includes).

For module-to-file mappings, see [module_mapping.md](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/docs/module_mapping.md). For high-level project status, see [status.md](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/docs/status.md).

---

## API Coverage Overview

GoCD uses a media-type-based API versioning strategy. Clients must request the specific version using the `Accept` header. Our routing in [router.ex](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/router.ex) mounts compatible endpoints under `/api` and `/go/api` scopes to support both native API calls and clients/plugins hardcoded to GoCD's default pathing.

### Legend
*   **Implemented (✅)**: Endpoint exists, operates correctly, matches GoCD request/response structure and content type.
*   **Partially Implemented (⚠️)**: Endpoint exists but lacks some filters, sub-routes, or strict GoCD validation.
*   **Not Implemented (❌)**: Endpoint does not exist in our Phoenix app yet.
*   **Deferred / N/A (💤)**: Endpoint corresponds to features we do not support or plan to support (e.g., legacy plugins, specific enterprise features).

---

## Detailed Coverage Matrix

| # | GoCD API Reference | Accept Header (Media Type) | Status | Phoenix Controller & Actions | Notes |
|---|--------------------|----------------------------|--------|------------------------------|-------|
| 1 | **Access Tokens** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Used for personal access tokens. Not implemented. |
| 2 | **Agent Health** | *Internal* | ❌ | *None* | Tracks agent CPU/Memory/Disk. Not implemented. |
| 3 | **Agents** | `application/vnd.go.cd.v7+json` | ✅ | [AgentController](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/api/agent_controller.ex) | Complete implementation of GET (list/show), PATCH (update), DELETE (soft delete), PUT (enable/disable). Normalizes config states. |
| 4 | **Artifact Store** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configuration of external artifact plugins. Not implemented. |
| 5 | **Artifacts Config** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Settings for artifact purges. Not implemented. |
| 6 | **Artifacts / Files** | *Raw Octet Stream / Multi-part* | ✅ | [ArtifactsController](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/artifacts_controller.ex) | Directory zipping, streaming downloads, secure uploads, Zip Slip protection, and DB-backed console log integration. |
| 7 | **Authentication** | *Session/Header-based* | ❌ | *None* | Session-based authentication endpoints. |
| 8 | **Authorization Configurations** | `application/vnd.go.cd.v2+json` | ❌ | *None* | Management of auth plugins/LDAP. Not implemented. |
| 9 | **Backup Config** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configuration of automatic backups. Not implemented. |
| 10 | **Backups** | `application/vnd.go.cd.v2+json` | ❌ | *None* | Triggering and fetching server backups. Not implemented. |
| 11 | **Changelog** | *None* | ❌ | *None* | VSM changelogs. Not implemented. |
| 12 | **Cluster Profiles** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configuration of elastic agent cluster profiles. Not implemented. |
| 13 | **Config Repos** | `application/vnd.go.cd.v4+json` | ❌ | *None* | Management of configuration repositories. Not implemented. |
| 14 | **Configuration** | *Multi-part XML* | ❌ | *None* | Upload and download of full `cruise-config.xml`. |
| 15 | **Current User** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Details of currently authenticated user. Not implemented. |
| 16 | **Dashboard** | `application/vnd.go.cd.v4+json` | ❌ | *None* | REST endpoint for dashboard data. The UI uses LiveView directly. |
| 17 | **Default Job Timeout** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Server-wide job timeout config. Not implemented. |
| 18 | **Elastic Agent Profiles** | `application/vnd.go.cd.v2+json` | ❌ | *None* | Profiles for elastic agents. Not implemented. |
| 19 | **Encryption** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Encrypts plain text values. Not implemented. |
| 20 | **Environment Config** | `application/vnd.go.cd.v3+json` | ❌ | *None* | CRUD operations for GoCD environments. |
| 21 | **Feeds** | `application/atom+xml` | ❌ | *None* | Pipeline and stage XML feeds. Not implemented. |
| 22 | **Jobs / Job Instance** | `application/vnd.go.cd.v1+json` | ⚠️ | [JobController](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/api/job_controller.ex) | Custom scheduling endpoint `/api/jobs/schedule` implemented. GoCD's history, active jobs, and transition APIs are not yet exposed. |
| 23 | **Mailserver Config** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configures SMTP details. Not implemented. |
| 24 | **Maintenance Mode** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Puts server in maintenance mode. Not implemented. |
| 25 | **Materials Notify** | *Webhook* | ❌ | *None* | Notifies about repo commits. |
| 26 | **Materials Webhook** | *Webhook* | ❌ | *None* | Integrates GitHub/GitLab webhooks. |
| 27 | **Materials** | `application/vnd.go.cd.v2+json` | ❌ | *None* | Lists material configurations and modifications. |
| 28 | **Notification Filters** | `application/vnd.go.cd.v2+json` | ❌ | *None* | User notification settings. Not implemented. |
| 29 | **Package Config** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configures package material packages. Not implemented. |
| 30 | **Package Repository** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configures package repository. Not implemented. |
| 31 | **Permissions** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configuration of resource permissions. Not implemented. |
| 32 | **Pipeline Config** | `application/vnd.go.cd.v11+json` | ❌ | *None* | CRUD operations for pipeline definitions. |
| 33 | **Pipeline Group Config** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Configures pipeline groups. Not implemented. |
| 34 | **Pipeline Groups** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Lists pipeline groups. Not implemented. |
| 35 | **Pipeline Instances** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Gets pipeline instance details. Not implemented. |
| 36 | **Pipelines (Operations)** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Endpoints to pause, unpause, and unlock pipelines. (Dashboard plays directly via context). |
| 37 | **Pluggable SCM** | `application/vnd.go.cd.v4+json` | ❌ | *None* | Configuration of SCM plugins. Not implemented. |
| 38 | **Plugin Info** | `application/vnd.go.cd.v7+json` | 💤 | *None* | Deferred (GoCD's plugin infra is not currently implemented). |
| 39 | **Plugin Settings** | `application/vnd.go.cd.v1+json` | 💤 | *None* | Deferred. |
| 40 | **Roles** | `application/vnd.go.cd.v3+json` | ❌ | *None* | CRUD for authorization roles. Not implemented. |
| 41 | **Secret Configs** | `application/vnd.go.cd.v3+json` | ❌ | *None* | Configuration of secret managers. Not implemented. |
| 42 | **Server Health Messages** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Gets server warnings/errors. Not implemented. |
| 43 | **Server Health** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Basic server health endpoint. |
| 44 | **Site URLs Config** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Sets site URL configurations. Not implemented. |
| 45 | **Stage Instances** | `application/vnd.go.cd.v3+json` | ❌ | *None* | Fetches stage history. Not implemented. |
| 46 | **Stages** | `application/vnd.go.cd.v2+json` | ❌ | *None* | Stage operations (cancel, rerun). |
| 47 | **System Admins** | `application/vnd.go.cd.v2+json` | ❌ | *None* | Configures system administrators. Not implemented. |
| 48 | **Template Config** | `application/vnd.go.cd.v7+json` | ❌ | *None* | CRUDS for pipeline templates. Not implemented. |
| 49 | **Users** | `application/vnd.go.cd.v3+json` | ❌ | *None* | CRUD operations for users. Not implemented. |
| 50 | **Version** | `application/vnd.go.cd.v1+json` | ❌ | *None* | Version API details. **Planned.** |

---

## Detailed Implementation Breakdown

### 1. Agents API (V7)
*   **Media Type**: `application/vnd.go.cd.v7+json`
*   **Path**: `/api/agents` and `/go/api/agents`
*   **Actions**:
    *   `GET /`: List all agents (supported parameters: `active="true"` filter).
    *   `GET /:uuid`: Show agent details.
    *   `PATCH /:uuid`: Update agent configuration (hostname, resources, environments, config state).
    *   `DELETE /:uuid`: Soft delete/deregister agent.
    *   `PUT /:uuid/enable`: Enable agent.
    *   `PUT /:uuid/disable`: Disable agent.
*   **Implementation Location**: [AgentController](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/api/agent_controller.ex) & [AgentJSON](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/api/agent_json.ex).

### 2. Artifacts & Files API
*   **Path**: `/files/...`, `/go/files/...`, `/remoting/files/...`
*   **Actions**:
    *   `GET /:pipeline/:counter/:stage/:stage_counter/:job/*path`: Fetch artifact. If path matches `cruise-output/console.log`, logs are read directly from the database schema `AgentJobRun` rather than disk, ensuring centralized log integration. Directories are returned as a JSON index or zipped archive based on file extensions/Accept headers.
    *   `POST /:pipeline/:counter/:stage/:stage_counter/:job/*path`: Upload file or zip file. Zips are decompressed safely with Zip Slip traversal protection.
    *   `PUT /:pipeline/:counter/:stage/:stage_counter/:job/*path`: Append data to files/logs.
*   **Implementation Location**: [ArtifactsController](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/artifacts_controller.ex).

### 3. Agent Remoting API (HTTP Internal)
*   **Path**: `/remoting/api/agent/...` and `/go/remoting/api/agent/...`
*   **Actions**:
    *   `POST /ping`: Ping from agent to report state and heartbeat.
    *   `POST /get_cookie`: Retrieves agent cookies.
    *   `POST /get_work`: Requests work assignments.
    *   `POST /report_current_status`: Updates execution status.
    *   `POST /report_completing`: Marks stage transitions.
    *   `POST /report_completed`: Marks build completion.
*   **Implementation Location**: [AgentRemotingController](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/agent_remoting_controller.ex).

### 4. Jobs Scheduling API
*   **Path**: `/api/jobs/schedule` and `/go/api/jobs/schedule`
*   **Actions**:
    *   `POST /`: Manually enqueues a job instance for agent matching and execution.
*   **Implementation Location**: [JobController](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd_web/controllers/api/job_controller.ex) and [Scheduler](file:///Users/dmitryledentsov/src/gocd-rewrite/ex_gocd/lib/ex_gocd/scheduler.ex).

---

## Key Coverage Gaps & Roadmap

1.  **Version API (`/api/version`)**:
    *   *Purpose*: Provides GoCD server version info. Required for some agent bootstrappers and tooling.
    *   *Plan*: Add `/api/version` returning standard GoCD payload structure matching `versions.yml` specification.
2.  **Server Statistics / Status API (`/api/stats`)**:
    *   *Purpose*: Crucial for monitoring rewrite state, resource usage, active agents, queue depths, and database metrics.
    *   *Plan*: Add a new statistics endpoint that integrates with telemetry modules.
3.  **Pipeline Operations API (`/api/pipelines/:pipeline_name/pause`, `/api/pipelines/:pipeline_name/schedule`)**:
    *   *Purpose*: Allows external triggers and pipeline locks.
    *   *Plan*: Expose controllers wrapping the existing `ExGoCD.Pipelines` context actions.
4.  **Environments and Config Repos**:
    *   *Purpose*: Facilitates infrastructure-as-code configuration.
    *   *Plan*: Add REST controllers to manage Ecto environment records.
