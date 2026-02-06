# ex_gocd Rewrite Prioritization Plan

## Core Principle

**Always maintain a working, deployable system** with incrementally increasing quality and functionality.

## Prioritization Strategy

### Phase 0: Foundation (COMPLETE)

**Goal**: Establish basic Phoenix application with GoCD look and feel

- [x] Phoenix project setup with LiveView
- [x] Basic routing and page structure
- [x] GoCD CSS/styling integration (fonts, colors, header)
- [x] Responsive design foundation
- [x] Accessibility baseline (ARIA, keyboard nav)
- [x] Docker Compose for local development
- [x] Database setup (Postgres + SQLite support)

**Deliverable**: Empty but styled application shell that looks like GoCD

---

### Phase 1: Dashboard UI (COMPLETE)

**Goal**: Complete visual parity with GoCD dashboard (no backend data yet)

#### 1.1 Header & Navigation

- [x] Site header with correct menu items
- [x] Active state indicators (purple bar)
- [x] User dropdown menu (placeholder)
- [x] Mobile responsive navigation

#### 1.2 Dashboard Layout

- [x] Dashboard LiveView shell
- [x] Custom dropdown component (grouping selector)
- [x] Pipeline group cards (static mockup)
- [x] Pipeline cards with stages (static mockup)
- [x] Search functionality (client-side filter)
- [x] Empty state messaging

#### 1.3 Testing Foundation

- [x] LiveView mount and render tests
- [x] Component rendering tests
- [x] Accessibility compliance tests
- [x] Responsive design tests

**Deliverable**: Pixel-perfect dashboard UI with mock data, fully tested

---

### Phase 2: Core Domain Model

**Goal**: Implement foundational GoCD concepts in Ecto schemas

**CRITICAL**: Must follow exact GoCD domain model and terminology. See [rewrite.md](./rewrite.md) and [schema_comparison.md](./schema_comparison.md) for detailed requirements.

#### 2.1 Basic Schema

```elixir
# Correct GoCD hierarchy - from smallest to largest:
1. Task (single command: ant, rake, shell script)
2. Job (multiple tasks, runs in order on one agent)
3. Stage (multiple jobs, run in parallel)
4. Pipeline (multiple stages, run sequentially)
5. Material (Git, SVN, Pipeline Dependency, Timer, etc.)
6. PipelineInstance (single execution with counter)
7. StageInstance (execution of stage within pipeline instance)
8. JobInstance (execution of job within stage instance)
```

#### 2.2 Relationships

- Pipeline → Stages (has_many)
- Stage → Jobs (has_many)
- Job → Tasks (has_many)
- Pipeline → Materials (many_to_many)
- Pipeline → PipelineInstances (has_many)
- PipelineInstance → StageInstances (has_many)
- StageInstance → JobInstances (has_many)
- Instance tracking for execution history

#### 2.3 Testing

- Schema validation tests
- Relationship integrity tests
- Changeset validation tests
- Database constraint tests

**Deliverable**: Core domain model matching GoCD source code exactly

---

### Phase 3: Dashboard with Real Data

**Goal**: Connect dashboard UI to database

#### 3.1 Data Layer

- [ ] Context modules (Pipelines, Stages, Materials)
- [ ] Query functions (list, get, filter)
- [ ] Seed data for development
- [ ] Database migrations

#### 3.2 LiveView Integration

- [ ] Load pipelines from DB in `mount/3`
- [ ] Filter by pipeline group
- [ ] Search pipelines by name
- [ ] Real-time updates via PubSub

#### 3.3 Testing

- [ ] Context function tests
- [ ] LiveView integration tests with DB
- [ ] Query performance tests
- [ ] Concurrent access tests

**Deliverable**: Dashboard displaying real pipeline data from database

---

### Phase 4: Pipeline State Machine

**Goal**: Implement pipeline scheduling and execution

#### 4.1 State Management

- [ ] PipelineInstance states (Idle, Building, Passed, Failed)
- [ ] Stage states (NotRun, Scheduled, Building, Passed, Failed, Cancelled)
- [ ] Job states (Scheduled, Assigned, Building, Completed)
- [ ] GenStateMachine for pipeline lifecycle

#### 4.2 Status Tracking

- [ ] Pipeline status aggregation
- [ ] Stage result calculation
- [ ] Build history tracking
- [ ] Change tracking (materials)

#### 4.3 Testing

- [ ] State transition tests
- [ ] Status calculation tests
- [ ] Concurrent pipeline execution tests
- [ ] Race condition tests

**Deliverable**: Pipelines can be triggered and track state (no actual execution yet)

---

### Phase 5: Material Polling

**Goal**: Monitor Git repositories for changes

#### 5.1 Git Material

- [ ] Git repository polling (GenServer)
- [ ] Commit detection and parsing
- [ ] Material fingerprinting
- [ ] Modification tracking

#### 5.2 Scheduling

- [ ] Automatic pipeline trigger on material change
- [ ] Manual trigger support
- [ ] Material dependency resolution

#### 5.3 Testing

- [ ] Git polling tests (with test repo)
- [ ] Material change detection tests
- [ ] Trigger logic tests

**Deliverable**: Pipelines automatically trigger on Git commits

---

### Phase 6: Agent Communication

**Goal**: Basic agent registration and job assignment

#### 6.1 Agent Protocol

- [ ] Agent registration endpoint
- [ ] Heartbeat mechanism (GenServer)
- [ ] Agent status tracking (Idle, Building, Lost)

#### 6.2 Job Assignment

- [ ] Job queue (GenServer or ETS)
- [ ] Agent selection algorithm
- [ ] Job assignment API

#### 6.3 Basic Go Agent

- [ ] Agent in Go (no cgo)
- [ ] Registration logic
- [ ] Heartbeat loop
- [ ] Job polling

#### 6.4 Testing

- [ ] Agent registration tests
- [ ] Heartbeat timeout tests
- [ ] Job assignment tests
- [ ] Agent failover tests

**Deliverable**: Agents can register and receive job assignments

---

### Phase 7: Job Execution

**Goal**: Agents execute jobs and report results

#### 7.1 Job Execution

- [ ] Task execution in Go agent
- [ ] Console log streaming (LiveView Streams)
- [ ] Artifact upload
- [ ] Job result reporting

#### 7.2 Server-side

- [ ] Job status updates via PubSub
- [ ] Log aggregation and storage
- [ ] Artifact storage
- [ ] Build result processing

#### 7.3 Testing

- [ ] End-to-end pipeline execution tests
- [ ] Log streaming tests
- [ ] Artifact handling tests
- [ ] Failure recovery tests

**Deliverable**: Complete pipeline execution flow working

---

### Phase 8: Pipeline Configuration

**Goal**: Web UI for pipeline management

#### 8.1 Config UI

- [ ] Pipeline create/edit forms
- [ ] Stage configuration
- [ ] Job and task configuration
- [ ] Material configuration

#### 8.2 Validation

- [ ] Config validation logic
- [ ] Circular dependency detection
- [ ] Permission checks

#### 8.3 Testing

- [ ] Form validation tests
- [ ] Config save/load tests
- [ ] Permission enforcement tests

**Deliverable**: Pipelines configurable via web UI

---

### Phase 9: Advanced Features

**Goal**: Essential GoCD features for production use

#### 9.1 Value Stream Map

- [ ] Dependency graph calculation
- [ ] VSM visualization
- [ ] Pipeline dependency UI

#### 9.2 Environments

- [ ] Environment schema
- [ ] Agent-environment association
- [ ] Environment-based deployments

#### 9.3 Templates

- [ ] Pipeline templates
- [ ] Template parameters
- [ ] Template instantiation

#### 9.4 Testing

- [ ] VSM calculation tests
- [ ] Environment isolation tests
- [ ] Template expansion tests

**Deliverable**: Production-ready feature set

---

### Phase 10: Production Hardening

**Goal**: Enterprise-grade reliability and observability

#### 10.1 Observability

- [ ] Telemetry for all domain events
- [ ] Prometheus metrics export
- [ ] Distributed tracing
- [ ] Performance dashboards

#### 10.2 Reliability

- [ ] Database connection pooling tuning
- [ ] Graceful degradation
- [ ] Circuit breakers for external services
- [ ] Backup and restore

#### 10.3 Security

- [ ] Authentication (local + OAuth)
- [ ] Authorization (role-based)
- [ ] Secrets management
- [ ] Audit logging

#### 10.4 Testing

- [ ] Load testing
- [ ] Chaos engineering tests
- [ ] Security penetration tests
- [ ] Disaster recovery tests

**Deliverable**: Production-ready GoCD rewrite

---

## Working System Milestones

| Milestone | Description              | Can Deploy? | Can Use?        |
| --------- | ------------------------ | ----------- | --------------- |
| **M1**    | Styled UI shell          |             | View only       |
| **M2**    | Dashboard with mock data |             | Explore UI      |
| **M3**    | Dashboard with DB data   |             | View pipelines  |
| **M4**    | Pipeline state tracking  |             | Track status    |
| **M5**    | Material polling         |             | Auto-trigger    |
| **M6**    | Agent registration       |             | See agents      |
| **M7**    | Job execution            |             | **Full CI/CD**  |
| **M8**    | Config UI                |             | Self-service    |
| **M9**    | Advanced features        |             | Production-lite |
| **M10**   | Production hardening     |             | **Enterprise**  |

## Testing Strategy

### Test Pyramid

```
        /\
       /  \  E2E (few)
      /____\
     /      \
    / Integ. \ (some)
   /          \
  /____________\
 /    Unit      \ (many)
/______________\
```

### Coverage Targets

- **Unit tests**: 80%+ coverage
- **Integration tests**: Critical paths
- **E2E tests**: Happy path + major error scenarios
- **Property tests**: Core algorithms (ExCheck)

### Testing Cadence

- **Every commit**: Unit + integration tests (CI)
- **Every PR**: Full test suite + linting
- **Pre-release**: E2E + performance + security
- **Continuous**: Mutation testing (background)

## Quality Gates

### Code Merge Requirements

1.  All tests pass
2.  No compiler warnings
3.  Code formatted (`mix format`)
4.  Credo checks pass
5.  Documentation updated
6.  status.md updated

### Phase Completion Requirements

1.  All deliverables complete
2.  Test coverage meets targets
3.  Documentation complete
4.  Demo/showcase prepared
5.  Performance acceptable
6.  No known critical bugs

## Current Focus

**Phase 2: Domain Model - RESET & REPLANNING** (Week of Feb 6, 2026)

Phase 1: COMPLETE!

- Dashboard UI with full test coverage

Phase 2: IN PROGRESS - Schema Design

- ⚠️ Initial schema attempt reset - didn't match GoCD model
- Added comprehensive domain model documentation to rewrite.md
- Key learnings:
- Task must be a separate entity (was embedded in Job)
- Need Instance tables for Pipeline, Stage, Job (for execution tracking)
- Must use exact GoCD terminology and status values
- Hierarchy: Task → Job → Stage → Pipeline

**Next Steps**:

1. Review GoCD source code for exact schema
2. Create schema following GoCD model precisely
3. Implement with tests from the start

**Next Up**: Phase 2 (Core Domain Model - proper implementation)

## Guiding Principles

1. **Working Software Over Perfect Software**
   - Ship incrementally
   - Refactor continuously
   - Gather feedback early

2. **Test-Driven Development**
   - Write tests first when possible
   - Red-Green-Refactor cycle
   - Tests as living documentation

3. **Clean Architecture**
   - Domain logic in contexts
   - UI in LiveViews/Components
   - Thin controllers
   - Rich domain models

4. **Phoenix Patterns**
   - GenServers for stateful processes
   - PubSub for decoupling
   - Ecto for data
   - LiveView for UI

5. **Continuous Learning**
   - Study GoCD's design decisions
   - Adapt patterns to Elixir/Phoenix
   - Document trade-offs
   - Share knowledge

## Risk Management

### High-Risk Items

1. **Performance at scale** → Load testing early, optimize queries
2. **Agent communication protocol** → Design carefully, version from start
3. **Database schema migrations** → Plan schema carefully, use up/down migrations
4. **Real-time updates** → Test PubSub under load, handle disconnections

### Mitigation Strategies

- Spike high-risk items early
- Create throwaway prototypes
- Benchmark critical paths
- Design for failure from day one
