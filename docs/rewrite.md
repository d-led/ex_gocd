# Plan

## Motivation

- GoCD is an outstanding Continuous Delivery server with outstanding language, concepts and implementation, yet the stack is somewhat outdated.

## Rough Plan

- to counter the modern dilution of the concepts and revive GoCD, let's rewrite it into [Phoenix Framework](https://www.phoenixframework.org/) ([docs](https://hexdocs.pm/phoenix/overview.html)) and keep the overall architecture and UI style of GoCD but rewrite it into the current favorite [DaisyUI](https://daisyui.com/docs/install/phoenix/?lang=en) in Phoenix, with [LiveView](https://hexdocs.pm/phoenix_live_view/welcome.html) for simple live view updates.
- try to avoid javascript and focus on rewriting the UI into LiveView.
- use LiveView PubSub for things to be distributed to all connected LiveView clients e.g. for notifications. Where applicable and doable, use [LiveView Streams](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/4), e.g. for logs.
- as a plan, let's keep a [status.md](./status.md) where we'll put a table of all directories and files from [gocd source](../../gocd) and will keep track of the corresponding places in [this source](..) to build an incremental phoenix-rewrite (pun intended).
- For the agent, let's by default build it in Go, built without `cgo` as a standalone statically linked binary
- As for SCM systems, let's only focus on git but not exclude the option to implement others.
- for the rest, let's keep the overall architecture, but use [Elixir](https://elixirschool.com/en/lessons/advanced/otp_concurrency)/[Phoenix](https://elixirschool.com/blog/tag/phoenix)-native patterns, e.g like [GenStateMachine](https://hexdocs.pm/gen_state_machine/GenStateMachine.html) and [GenServer](https://elixirschool.com/en/lessons/advanced/otp_concurrency). Polling is just a delayed self-message in GenServer.
- We'll slowly and continuously build it up, concentrating on the same testability, test coverage as the original GoCD. We can also follow the testing strategy.
- As for the database, we'll stick to [Ecto](https://hexdocs.pm/phoenix/ecto.html), run postgres in docker compose locally, but support / have examples for both sqlite and postgres in the repo.
- We'll use [Phoenix telemetry](https://hexdocs.pm/phoenix/telemetry.html) to observe both the server but also the domain events / spans, if possible. That way we can try to minimize the dependencies as well.
- When finishing each atomic task, add the most important entries in terse form in [status.md](./status.md) "Progress Log". Do not add something to the progress log if it's already part of it.
- Make sure to make the app still work for a variety of screens, touch screen and keep it accessible.
- TEST at all levels that make sense! Try to stay close to the specification in the original GoCD repo. Test [LiveViews](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html) and [Ecto](https://hexdocs.pm/ecto/testing-with-ecto.html) apart from the unit and integration tests of modules. Make sure the tests run in Github Actions and report a table of results.
- For the API spec, we need to stick to the same spec but without the backward compatibility (just latest version): [api.go.cd](../../api.go.cd)
- Validate data properly. Users need to know what exactly is wrong and where. GoCD is optimized for immediate understandability and insight into failures.
- Strictly follow the latest GoCD API spec and the DB schema and its connection to the conceps and the domain language of GoCD. It's what we must continuously check that we preserve it.
- compared to the original with its static, versioned config, let's also make both the server and the agent a [12-factor app](https://12factor.net/config) and let it be configured via the environment. We can still version the resulting config when it changes upon e.g. restart.
- the Agent in [../agent](../agent/) might profit from cross-checking with https://github.com/gocd-contrib/gocd-golang-agent but we'll use modern go approaches and libraries

## CRITICAL: Protocol Compatibility

### Absolute Requirement: Binary Protocol Compatibility

**Both the agent and Phoenix server MUST be 100% compatible with original GoCD's agent protocol and API.**

This ensures:
- Our Go agent can register with original GoCD server
- Our Phoenix server can accept original GoCD agents
- API clients can use either server interchangeably
- Zero migration friction for users

### Agent Protocol (WebSocket + Custom Protocol)

**Registration** (original GoCD):
- Endpoint: `POST /admin/agent` (NOT `/api/agents`)
- Format: `application/x-www-form-urlencoded` (form data, NOT JSON)
- Fields: `hostname`, `uuid`, `location`, `usablespace`, `agentAutoRegisterKey`, `agentAutoRegisterResources`, `agentAutoRegisterEnvironments`, `supportsBuildCommandProtocol`
- Token flow: `GET /admin/agent/token?uuid={uuid}` → then registration with token
- Response: JSON with `AgentPrivateKey` and `AgentCertificate`

**Communication**:
- Protocol: WebSocket at `/agent-websocket` (NOT REST/JSON polling)
- Scheme: `wss://` for HTTPS servers
- Message format: Custom JSON protocol with `action` field

**Protocol Messages** (see [gocd-golang-agent/protocol](https://github.com/gocd-contrib/gocd-golang-agent/tree/main/protocol)):
- `setCookie` - Server sets agent cookie
- `ping` - Agent heartbeat with `AgentRuntimeInfo`
- `build` - Server assigns job to agent
- `reportCurrentStatus` - Agent reports job progress
- `reportCompleting` - Agent signals job completion starting
- `reportCompleted` - Agent reports final job result
- `cancelBuild` - Server cancels running job
- `reregister` - Server requests agent re-registration
- `acknowledge` - Agent ACKs received message

**Console Logs**:
- Upload via HTTP POST to build-specific console URL
- Buffered with 5-second flush interval
- Timestamp prefix: `HH:mm:ss.SSS`

**Artifacts**:
- Upload: HTTP POST multipart/form-data
- Fields: `zipfile` (zipped source), `file_checksum` (MD5)
- Retry logic with `attempt` query param
- Download: HTTP GET with checksum verification

### REST API (HTTP + JSON)

**Must match original GoCD API spec**: [api.go.cd](../../api.go.cd)

**Critical endpoints**:
- Agent listing: `GET /api/agents` (versioned, e.g., `/api/v7/agents`)
- Pipeline groups: `GET /api/config/pipeline_groups`
- Pipeline config: `GET /api/admin/pipelines/{name}`
- Value Stream Map: `GET /api/pipelines/{name}/value_stream_map`

**API versioning**:
- Header: `Accept: application/vnd.go.cd.v7+json`
- URL prefix: `/api/v7/...`
- Maintain latest version only (no backward compatibility burden)

### Implementation Strategy

**Go Agent**:
1. Use WebSocket library (e.g., `gorilla/websocket`)
2. Implement custom protocol message types from golang-agent reference
3. Form-based registration with token flow
4. Ping every 10 seconds with runtime info
5. Process build messages, execute tasks, report status
6. Upload console logs and artifacts via multipart HTTP

**Phoenix Server**:
1. WebSocket endpoint: `Phoenix.Socket` at `/agent-websocket`
2. Handle agent protocol messages in socket handler
3. Form-based registration endpoint: controller action
4. REST API: versioned controllers matching api.go.cd spec
5. Console log streaming: accept HTTP POST, store, serve via API
6. Artifact storage: handle multipart uploads, serve downloads

### Validation

**Test matrix**:
- ✅ Go agent registers with original GoCD server
- ✅ Go agent registers with Phoenix server
- ✅ Original Java agent registers with Phoenix server
- ✅ API clients work with both servers identically

**Reference implementation**: [gocd-contrib/gocd-golang-agent](https://github.com/gocd-contrib/gocd-golang-agent)
- Copy protocol message definitions
- Copy WebSocket connection logic
- Copy registration flow
- Use modern Go libraries for everything else (go-git, etc.)

**Reverse-engineering from gocd source** (this repo's `gocd/`):
- **Remoting**: Original Java agent uses HTTP POST to `/remoting/ping`, `/remoting/get_work`, etc. (`RemotingClient`, `BuildRepositoryRemoteImpl`). We use WebSocket + JSON (gocd-golang-agent style) for the rewrite; semantics (ping → update runtime, report status, etc.) match.
- **LostContact**: In gocd, `AgentInstance` has `lastHeardTime`; `refresh()` sets runtime status to `LostContact` when `isTimeout(lastHeardTime)`. We have a live WebSocket: when the agent's **channel process** exits, we call `Agents.mark_lost_contact(uuid)` from `AgentChannel.terminate/2`, so the DB state becomes "LostContact" and the UI updates immediately. Presence also removes the agent from the presence list when the channel process exits (we track the channel pid).
- **Scheduling**: In gocd, `BuildAssignmentService` holds a queue of `JobPlan` (from `orderedScheduledBuilds()`); `WorkFinder` reacts to idle agents and calls `assignWorkToAgent`; the agent gets work via `get_work` (HTTP) or we push over WebSocket. We implement the same idea with `ExGoCD.Scheduler`: an in-memory queue of job specs; when an agent pings with `runtimeStatus` "Idle", we call `Scheduler.try_assign_work(uuid)`, which finds a matching job (by resources/environments), creates the run, and pushes a `build` message to the agent. Jobs are enqueued via `Scheduler.schedule_job(spec)` (e.g. from the UI "Schedule test job").

## CRITICAL: Domain Language and Data Model Fidelity

### Absolute Requirements

**We MUST use EXACTLY the same domain language and data model as the original GoCD.**

This is not negotiable. GoCD's conceptual model is one of its greatest strengths, and users depend on this consistency. Any deviation will:

- Break mental models that users have built over years
- Make documentation and learning materials inconsistent
- Create confusion during migration from original GoCD
- Violate the core principle: this is a rewrite, not a redesign

### GoCD Domain Hierarchy (from smallest to largest)

Based on [GoCD Concepts Documentation](../../docs.go.cd/content/introduction/concepts_in_go.md):

1. **Task** - A single action/command (e.g., `ant compile`, `rake test`, shell script)
   - The atomic unit of work
   - Runs sequentially within a job
   - Each task is independent (own process, environment vars don't carry over)
   - Filesystem changes DO carry over to next task

2. **Job** - Multiple tasks that run in order
   - Contains 1+ tasks
   - Fails if any task fails
   - Can publish **Artifacts** (files/directories) after completion
   - Has **Resources** (tags) for agent matching
   - Runs on a single agent

3. **Stage** - Multiple jobs that can run in parallel
   - Contains 1+ jobs
   - Jobs are independent and parallelizable
   - Fails if any job fails
   - Has **Approval Type**: "success" (automatic) or "manual"
   - Can fetch artifacts from previous stages

4. **Pipeline** - Multiple stages that run sequentially
   - Contains 1+ stages
   - Stages run in order
   - Fails if any stage fails
   - Has a **Pipeline Group** for organization
   - Triggered by **Materials**
   - Each run creates a **Pipeline Instance** with incrementing counter
   - Can be used as a material for other pipelines (pipeline dependency)

5. **Materials** - Triggers for pipelines
   - Types: Git, SVN, Mercurial, Perforce, TFS, Pipeline Dependency, Package, Timer, Plugin
   - Polled for changes by GoCD Server
   - Trigger pipelines when changes detected
   - Pipeline can have multiple materials

6. **Pipeline Instance** - Single execution of a pipeline
   - Has unique counter (increments)
   - Has label (customizable, default `${COUNT}`)
   - Tracks:
     - Status (Building, Passed, Failed, Cancelled, Paused)
     - Who/what triggered it
     - When scheduled/completed
     - Material revisions used

### Supporting Concepts

7. **Artifacts**
   - Files/directories published by jobs
   - Stored by GoCD Server
   - Can be fetched by downstream stages/pipelines
   - Fetch Artifact Task ensures correct version is retrieved

8. **Agent** - Worker that executes jobs
   - Polls GoCD Server for assigned jobs
   - Executes tasks within jobs
   - Reports status back to Server
   - Has **Resources** (capabilities)
   - Can belong to **Environments**

9. **Resources** - Free-form tags for agent-job matching
   - Defined on agents (broadcast capabilities)
   - Defined on jobs (requirements)
   - Job only runs on agents with matching resources
   - E.g., "firefox", "linux", "docker", "nodejs"

10. **Environment** - Grouping and isolation mechanism
    - Rules:
      - Pipeline can belong to maximum ONE environment
      - Agent can belong to MULTIPLE environments or none
      - Agent only picks jobs from pipelines in its environments
      - Agent in environment cannot pick jobs from pipelines with no environment
    - Used for deployment stages (dev, staging, prod)

11. **Environment Variables**
    - User-defined variables available to tasks
    - Cascade and override:
      - Environment level (lowest priority)
      - Pipeline level
      - Stage level
      - Job level (highest priority)

12. **Template** - Reusable pipeline configuration
    - Define stages/jobs/tasks once
    - Multiple pipelines can use same template
    - Helps manage branches and large numbers of pipelines

### Data Model Requirements

When implementing schemas and database tables:

1. **Use exact GoCD terminology**
   - Table names: `pipelines`, `stages`, `jobs`, `tasks`, `materials`
   - Not: `builds`, `workflows`, `steps`, `sources`

2. **Maintain hierarchy**
   - Pipeline → Stage → Job → Task (parent-child relationships)
   - Pipeline Instance → Stage Instance → Job Instance
   - Each instance level tracks its own execution state

3. **Preserve relationships**
   - Pipeline ↔ Materials (many-to-many)
   - Pipeline → Pipeline Instances (one-to-many)
   - Pipeline belongs to one Pipeline Group (string, not relation)
   - Job publishes Artifacts (one-to-many)
   - Job requires Resources (array of strings)
   - Agent has Resources (array of strings)

4. **Instance tracking**
   - Every pipeline run = Pipeline Instance (with counter)
   - Every stage run in that instance = Stage Instance
   - Every job run in that stage = Job Instance
   - Instances preserve history and enable value stream map

5. **Status values**
   - Use exact GoCD statuses: Building, Passed, Failed, Cancelled, Paused
   - Not: Running, Success, Error, Stopped

6. **Field naming**
   - `approval_type` not `approval_method`
   - `triggered_by` not `started_by`
   - `counter` not `build_number`
   - `label_template` not `version_pattern`

### Validation Checklist

Before implementing any schema:

- [ ] Check against concepts_in_go.md
- [ ] Verify terminology matches GoCD exactly
- [ ] Ensure hierarchy is preserved
- [ ] Confirm relationships are correct
- [ ] Validate status values match GoCD
- [ ] Test that instance tracking works

### Reference Documentation

Always refer to:

- [GoCD Concepts](../../docs.go.cd/content/introduction/concepts_in_go.md)
- [GoCD Configuration Reference](../../docs.go.cd/content/configuration/configuration_reference.html)
- Original GoCD database schema (when available)
- GoCD API documentation for field names

**When in doubt, check the original GoCD. Never invent new concepts or rename existing ones.**

## Design and Styling Approach

### Core Principle: Visual Fidelity to GoCD

We maintain pixel-level fidelity to the original GoCD UI. This is a rewrite, not a redesign. Users should feel immediately at home.

### CSS Strategy

**Direct conversion from GoCD source**:

- Copy SCSS files from `gocd/server/src/main/webapp/WEB-INF/rails/webpack/views/`
- Convert SCSS to standard CSS (replace variables, remove mixins, expand media queries)
- Preserve exact values: colors, spacing, font sizes, transitions
- Keep GoCD's class naming conventions where possible
- Store in `assets/css/gocd/` to clearly mark origin
- note https://hexdocs.pm/phoenix/asset_management.html

**What we copy**:

- Layout CSS (site_header, navigation, footers)
- Component styles (dropdowns, buttons, cards, modals)
- Color schemes and theme variables
- Typography and font specifications
- Responsive breakpoints and mobile styles
- Animation and transition timings
- Accessibility features (focus states, ARIA support)

**Conversion process**:

1. Identify SCSS file in GoCD source
2. Copy to `assets/css/gocd/[component].css`
3. Replace SCSS variables with CSS values (from `_variables.scss`)
4. Expand mixins inline
5. Convert nested selectors to flat CSS
6. Test against original GoCD at each breakpoint
7. Document source file in header comment

**Example conversion**:

```scss
// GoCD source: site_header.scss
.site-header {
  background: $site-header; // #000728
  @media (min-width: $screen-md) {
    // 768px
    height: 40px;
  }
}
```

```css
/* Converted from gocd/server/.../site_header.scss */
.site-header {
  background: #000728;
}
@media (min-width: 768px) {
  .site-header {
    height: 40px;
  }
}
```

### DaisyUI Role

**NOT used for GoCD UI components**. DaisyUI is available but secondary:

- Use for internal admin tools (if we build any)
- Use for developer-facing debugging UIs
- Do NOT use for user-facing GoCD interfaces
- Pipeline dashboard, agents, materials, etc. use pure GoCD CSS

**Why this approach**:

- GoCD has a distinctive, professional UI that users know
- Rewriting === preserving the experience
- DaisyUI would make it look generic/different
- GoCD's CSS is well-crafted and battle-tested

### Layout Structure

Follow GoCD's exact component hierarchy:

- Site header (fixed, 40px on desktop, 50px on mobile)
- Main navigation (left: menu items, right: help + user)
- Content area (dashboard, agents, materials, etc.)
- Modals and overlays (for confirmations, forms)

### Responsive Design

Match GoCD's breakpoints exactly:

- Mobile: < 768px
- Tablet: 768px - 991px
- Desktop: >= 992px

Preserve GoCD's mobile menu behavior:

- Hamburger button on mobile
- Slide-out navigation
- Touch-friendly 44px tap targets

### Component Mapping

| GoCD Component | Our Implementation           | CSS Source                   |
| -------------- | ---------------------------- | ---------------------------- |
| Site Header    | `layouts.ex` `site_header/1` | `site_header.css`            |
| Navigation     | Part of site_header          | `site_menu/index.scss` → CSS |
| Dashboard      | `dashboard_live.ex`          | TBD from GoCD                |
| Pipeline Cards | LiveView component           | TBD from GoCD                |
| Dropdowns      | Custom LiveView              | `dropdown.css` (adapted)     |

### Testing Visual Fidelity

For each component:

1. Open original GoCD: `http://localhost:8153/go/pipelines`
2. Open our version: `http://localhost:4000/`
3. Compare side-by-side at each breakpoint
4. Verify spacing, colors, fonts, hover states
5. Check keyboard navigation and accessibility
6. Adjust CSS until pixel-perfect

### When to Deviate

Only deviate from GoCD's CSS when:

- Adapting React/Mithril components to LiveView (structure only, keep styling)
- Removing Java/Spring-specific elements (server-side rendering artifacts)
- Adding Phoenix-specific features (LiveView loading states)
- Improving accessibility beyond GoCD's baseline

Always document deviations and reasoning.

## agent links

- https://daisyui.com/llms.txt
- [AGENTS.md](../AGENTS.md)
