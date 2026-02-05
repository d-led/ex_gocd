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
| `domain/`                           | Domain models           | ❌     | `lib/ex_gocd/domain/`               | Pipelines, Stages, Jobs, Materials |
| `common/`                           | Shared utilities        | ❌     | `lib/ex_gocd/`                      | Shared utilities across modules    |
| `config/config-api/`                | Configuration API       | ❌     | `lib/ex_gocd/config/`               | Config parsing, validation         |
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

---

## Next Steps

1. **Immediate (Phase 1.2 - Continue)**:
   - Create pipeline group card components (static mockup)
   - Create pipeline card components with stages (static)
   - Implement client-side search functionality
   - Add empty state messaging

2. **Phase 2: Core Domain Model**:
   - Define Ecto schemas for core domain (Pipeline, Stage, Job, Material, Agent)
   - Setup ExMachina for test fixtures
   - Write comprehensive schema tests

3. **Phase 3: Dashboard with Real Data**:
   - Implement context modules
   - Connect LiveView to database
   - Add seed data

4. **Later Phases**:
   - Implement basic config parsing
   - Create agent registration GenServer
   - Build material polling system
   - Implement pipeline scheduler
   - Develop agent (Go) with basic communication protocol

---

## Notes

- **Plugin System**: Deferred to later phase. Initial focus on core CD functionality
- **SCM Support**: Git only initially, can add others later
- **Database**: PostgreSQL primary, SQLite for dev/test
- **UI Framework**: DaisyUI with Phoenix LiveView (no React/SPA needed)
- **Agent**: Standalone Go binary, statically linked, no cgo
- **Telemetry**: Phoenix Telemetry for observability from day one
- **Testing**: Following GoCD's test pyramid - many unit tests, some integration, few E2E
