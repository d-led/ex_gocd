# Plan: External CI Pipeline Sync & Execution

> **Progress**: 🚧 Phase 0 in progress | Phase 1-6 not started

**TL;DR**: Make ex_gocd a run-to target for GitHub Actions and GitLab CI repos. Sync workflow/pipeline YAML files via config_repos, offer translation into GoCD native pipelines or direct execution via `act`/`gitlab-runner exec`. Add elastic agent support (Docker + K8s). Wizard-driven import with persisted selections and change detection.

---

### Phase 0: Data Model Foundation *(no dependencies)*

**0.1 Extend `config_repos` table**
- Add `source_type` column: `"gocd_pipeline"` (existing), `"github_actions"`, `"gitlab_ci"` (string, default `"gocd_pipeline"`)
- Add `plugin_id` column: nullable string, for future plugin extensibility
- Add `configuration` column: jsonb, stores source-type-specific config (e.g., gitlab CI `runner_tags`, GH Actions `runner_labels`)
- Migration: `priv/repo/migrations/YYYYMMDDHHMMSS_extend_config_repos.exs`

**0.2 New table: `config_repo_files`**
- Tracks individual workflow/pipeline files discovered in a config repo
- Columns: `config_repo_id` (FK→config_repos, on_delete: :delete_all), `path` (relative), `source_type` (`"github_workflow"`, `"gitlab_pipeline"`, `"gitlab_include"`, `"gitlab_template"`), `checksum` (SHA256), `last_seen_at`, `status` (`"new"`, `"active"`, `"deleted"`, `"modified"`), `raw_content` (text, cached last-fetched content), `parsed_at`
- Unique index on `[config_repo_id, path]`

**0.3 New table: `config_repo_file_selections`**
- Persists wizard choices per file
- Columns: `config_repo_file_id` (FK, unique), `mode` (`"translate"`, `"execute_act"`, `"execute_gitlab"`, `"skip"`), `selected_jobs` (jsonb — array of job/stage keys to include, null=all), `selected_triggers` (jsonb — which events to wire as materials), `overrides` (jsonb — manual overrides like env vars, resource tags)

**0.4 Add `config_repo_id` to `pipelines` table**
- Nullable FK: `config_repo_id` references `config_repos` (on_delete: :nilify)
- Also add `source_file_path` (string) — which file within the config repo produced this pipeline

**0.5 Extend `tasks` table**
- Add `task_type` value `"external"` to validation enum in `Task.changeset/2`
- Add `external_config` jsonb column — stores executor-specific config

**Relevant files:**
- `lib/ex_gocd/config_repos/config_repo.ex` — schema changes
- `lib/ex_gocd/pipelines/task.ex` — enum + jsonb
- `lib/ex_gocd/pipelines/pipeline.ex` — FK addition
- `lib/ex_gocd/config_repos.ex` — new context functions for files/selections

**Verification:**
1. Run `mix ecto.migrate` — all tables created, unique constraints enforced
2. Existing config_repo tests still pass (backward compat: `source_type` defaults to `"gocd_pipeline"`)
3. Insert a config_repo with `source_type: "github_actions"`, add files/selections — verify FK cascades

---

### Phase 1: Parsers — Shared IR + GH Actions & GitLab CI *(depends on Phase 0)*

**1.1 Define Intermediate Representation (IR)**
- New module: `ExGoCD.ConfigRepos.ExternalPipelineIR`
- Struct fields: `source_type`, `source_file`, `name`, `triggers` (list of `%{type: "push"|"pr"|"schedule"|"web", branches: [...], ...}`), `env_vars` (map), `stages` (ordered list of stage names), `jobs` (map of job_name → `%{stage:, needs:, image:, services:, steps:, artifacts:, ...}`), `includes` (list of resolved include paths)

**1.2 GitHub Actions workflow parser**
- New module: `ExGoCD.ConfigRepos.GitHubActionsParser`
- `parse_workflow(yaml_string, file_path) → {:ok, IR} | {:error, reason}`
- Parses `on:` (push, pull_request, schedule, workflow_dispatch, workflow_call), `jobs.<id>` (name, runs-on, needs, steps, env, container, services), `env:` (top-level)
- Step types: `run:` → exec step, `uses:` → plugin reference (warn/skip unknown actions)
- Matrix strategies: record metadata, warn, single parameterized pipeline

**1.3 GitLab CI parser with full include resolution**
- New modules: `ExGoCD.ConfigRepos.GitLabCIParser`, `ExGoCD.ConfigRepos.GitLabCIIncludeResolver`
- Include resolution: local, remote, project, template. Resolve `!reference` tags. Circular detection.
- Parse `stages:`, `variables:`, `workflow:`, jobs with `stage:`, `needs:`, `image:`, `services:`, `script:`, `before_script:`, `after_script:`, `artifacts:`, `rules:`

**1.4 Shared file discovery**
- New module: `ExGoCD.ConfigRepos.FileDiscovery`
- Clones/pulls repo, scans for `.github/workflows/*.yml` and `.gitlab-ci.yml`
- Reuses existing git infrastructure from `ExGoCD.Materials.ScmClient` / `GitClient`

**Relevant files:**
- `lib/ex_gocd/config_repos/external_pipeline_ir.ex` — new
- `lib/ex_gocd/config_repos/github_actions_parser.ex` — new
- `lib/ex_gocd/config_repos/gitlab_ci_parser.ex` — new
- `lib/ex_gocd/config_repos/gitlab_ci_include_resolver.ex` — new
- `lib/ex_gocd/config_repos/file_discovery.ex` — new

**Verification:**
1. Unit tests: parse sample GH Actions workflow → correct IR
2. Unit tests: parse sample GitLab CI with includes → correct IR, nested includes resolved
3. Unit tests: file discovery on a temp git repo with both `.github/workflows/` and `.gitlab-ci.yml`
4. Test include loops detected and gracefully errored

---

### Phase 2: Translation Engine *(depends on Phase 1)*

**2.1 Core translator behaviour**
- Behaviour: `ExGoCD.ConfigRepos.Translator` — `@callback translate(IR.t(), selections :: map()) :: {:ok, pipeline_attrs} | {:error, reason}`
- Orchestrator: `ExGoCD.ConfigRepos.TranslationEngine` — `translate_and_persist(config_repo, file_selections) → {:ok, count} | {:error, ...}`

**2.2 GitHub Actions → GoCD mapper**
- Workflow `name` → Pipeline `name` (sanitized)
- `on.push.branches` → Git material with branch filter
- `on.schedule` → Pipeline timer (cron)
- `on.workflow_dispatch` → Manual trigger
- Jobs → GoCD Stages (one per job; `needs` DAG for ordering)
- Job `runs-on` → Agent resource tags
- Job `env` → Stage/Job environment_variables
- Steps (`run:`) → Exec tasks
- Job `needs` → Stage dependencies (approval + fan-in)
- `services` → warn/skip

**2.3 GitLab CI → GoCD mapper**
- Pipeline name from `.gitlab-ci.yml` location or project name
- GitLab `stages:` → GoCD stages (ordered)
- Jobs assigned via `stage:` field
- `needs:` → Stage dependencies
- `rules:` → Material branch filters / conditional triggers
- `variables:` → Pipeline/Stage environment_variables
- `before_script:/script:/after_script:` → Exec tasks
- `artifacts:` → GoCD artifact configs
- `tags:` → Agent resource tags
- `image:/services:` → warn/skip in v1

**2.4 Selection-aware translation**
- `config_repo_file_selections` drives what's translated:
  - `mode: "skip"` → do nothing
  - `selected_jobs: ["build", "test"]` → only those jobs
  - `selected_triggers: ["push"]` → only push events
- First sync: translate everything → persist default selections

**2.5 Change detection on re-sync**
1. `FileDiscovery` → current file manifest
2. Compare with `config_repo_files` (checksum + path)
3. Emit diff: `{added: [...], removed: [...], modified: [...], unchanged: [...]}`
4. `removed` → mark `status: "deleted"`, warn, don't auto-delete pipelines
5. `modified` → mark `status: "modified"`, re-translate if mode=`"translate"`, else flag for wizard
6. `added` → insert with `status: "new"`, wizard presents them

**Relevant files:**
- `lib/ex_gocd/config_repos/translator.ex` — behaviour
- `lib/ex_gocd/config_repos/translation_engine.ex` — orchestrator
- `lib/ex_gocd/config_repos/github_actions_translator.ex` — new
- `lib/ex_gocd/config_repos/gitlab_ci_translator.ex` — new

**Verification:**
1. GH Actions workflow 2 jobs → 2-stage GoCD pipeline persisted
2. GitLab CI 3 stages, 5 jobs → correct ordering and dependencies
3. Re-sync detects file addition, deletion, modification
4. Selections respected — only selected jobs translated
5. Manual wizard-created pipeline unchanged by config repo translation

---

### Phase 3: Wizard UI *(depends on Phase 1, can parallel with Phase 2)*

**3.1 Config repo source type selection**
- Replace hardcoded config_repos demo data with real DB data
- "Add Config Repo" button → auto-detect source type or manual choice

**3.2 External CI repo wizard (new LiveView)**
- `ExGoCDWeb.ExternalCIRepoWizardLive` at `/admin/config_repos/new/external`
- Step 1: Repository URL, branch, source type
- Step 2: File discovery results with checkboxes, status badges, expandable job lists
- Step 3: Per-file mode (Translate/Execute/Skip), job/stage multi-select, trigger selection, overrides
- Step 4: Review & Save with summary and "Save & Sync" button

**3.3 Re-sync wizard**
- "Sync Config" button → wizard at Step 2 showing diff (new/modified/deleted)
- Pre-populated previous selections for unchanged files

**3.4 Config repo row enhancements**
- Columns: Source Type badge, File Count, Last Sync, Status, Actions

**Relevant files:**
- `lib/ex_gocd_web/live/external_ci_repo_wizard_live.ex` — new
- `lib/ex_gocd_web/live/admin_live.ex` — replace hardcoded data
- `lib/ex_gocd_web/router.ex` — add route

---

### Phase 4: Execution Engine *(depends on Phase 0.5, Phase 1; can parallel with Phase 2-3)*

**4.1 New task type: `"external"`**
- `external_config` jsonb: `{executor: "act" | "gitlab-runner", workflow_file, job_name, event}`
- Execute mode in wizard → pipeline with one stage, one job, one `"external"` task

**4.2 Agent-side: act executor**
- `agent/internal/executor/act/` — `RunAct(ctx, buildDir, workflowFile, jobName, event)`
- Shells out to `act -W <file> -j <job> -e <event>`
- Streams stdout/stderr as console output
- Checks for `act` binary at startup, reports capability

**4.3 Agent-side: gitlab-runner executor**
- `agent/internal/executor/gitlabrunner/` — `RunGitLabRunner(ctx, buildDir, jobName)`
- Shells out to `gitlab-runner exec docker <job>` or `gitlab-runner exec shell <job>`
- Prepares temporary `.gitlab-runner/config.toml`

**4.4 BuildCommand extension**
- `agent/pkg/protocol/websocket.go`: add `TaskType` and `ExternalConfig` to `BuildCommand`
- Agent `runBuildCommand()`: dispatch to act/gitlab-runner when `TaskType == "external"`

**4.5-4.6 Capability matching**
- Agent registers with `capabilities` array (`["act", "gitlab-runner", "docker"]`)
- Server stores in `agents.capabilities` jsonb
- Scheduler matches `external` tasks only to agents with right capability

**Relevant files:**
- `agent/internal/executor/act/act.go` — new
- `agent/internal/executor/gitlabrunner/gitlabrunner.go` — new
- `agent/internal/agent/agent.go` — dispatch
- `agent/pkg/protocol/websocket.go` — BuildCommand extension
- `agent/internal/config/config.go` — Capabilities field
- `agent/internal/registration/registration.go` — send capabilities
- `lib/ex_gocd/pipelines/task.ex` — `"external"` type
- `lib/ex_gocd/scheduler.ex` — capability matching
- `lib/ex_gocd/agents/agent.ex` — `capabilities` column

---

### Phase 5: Elastic Agent — Docker & K8s *(largely independent)*

**5.1 Go agent: elastic mode**
- `AGENT_ELASTIC_MODE=true`, registers with `elastic_agent_id`/`elastic_plugin_id`
- Listens for `provisionAgent` WebSocket action
- Provisions container/pod → child agent registers → does the build

**5.2 Server-side: Elastic Agent Profiles**
- Tables: `elastic_agent_profiles`, `cluster_profiles`
- Context modules: `ExGoCD.ElasticAgents`, `ExGoCD.Clusters`
- GoCD-compatible CRUD APIs

**5.3 Docker provisioner**
- `ExGoCD.ElasticAgents.DockerProvisioner`
- Pull image → create container with agent env vars → build → cleanup

**5.4 Kubernetes provisioner**
- `ExGoCD.ElasticAgents.K8sProvisioner`
- Create Job/Pod via K8s API → build → cleanup

**5.5 Job → Elastic Profile assignment**
- `Job.elastic_profile_id` set → scheduler calls `ElasticAgents.provision_agent(job)`
- Provision → register → assign → complete → destroy

**Relevant files:**
- `lib/ex_gocd/elastic_agents.ex` — new context
- `lib/ex_gocd/elastic_agents/docker_provisioner.ex` — new
- `lib/ex_gocd/elastic_agents/k8s_provisioner.ex` — new
- `lib/ex_gocd/clusters.ex` — new context
- `lib/ex_gocd/scheduler.ex` — elastic provisioning path
- `agent/cmd/root.go` — elastic mode flag
- `agent/internal/agent/agent.go` — elastic registration path

---

### Phase 6: Integration & Polish *(depends on Phase 2, 3, 4)*

- Wire Sync/Add buttons to wizard
- Material poller: external CI repos → change detection instead of pipeline triggers
- Webhooks: GitHub/GitLab push → auto-sync changes
- Admin UI: real data, sorting, search, status indicators

---

### Decisions & Assumptions

- **source_type on config_repos** — single table, differentiated by column. Simpler than polymorphic.
- **Translation is default**, execute mode is opt-in per workflow/job.
- **act and gitlab-runner are agent-side deps** — agent reports capabilities; scheduler matches.
- **Elastic provisioning is server-driven** — server creates containers/pods.
- **GitLab include resolution is full** with circular detection.
- **Existing gocd_pipeline config repos unchanged** — `source_type` defaults to `"gocd_pipeline"`.

### Deliberately Excluded from v1 — Detailed Rationale & v2 Direction

Each item below explains WHY it's excluded, HOW it currently behaves in v1, and WHAT the v2 plan looks like.

---

#### 1. GitHub Actions Matrix Strategy Full Expansion

**What it is**: GH Actions `strategy.matrix` generates a Cartesian product of all variable combinations, running a job instance for each. For example, `os: [ubuntu, macos]` × `node: [18, 20, 22]` produces 6 parallel job runs.

**v1 behavior**: The parser detects matrix definitions and records them as metadata on the IR job. The translator creates a single GoCD stage with a parameterized label (e.g., `${os}-${node}`) but does NOT create N separate pipelines or N parallel job instances. The matrix is preserved in the pipeline's `parameters` field for informational purposes. A warning is emitted: `"Matrix strategy detected but not expanded. Use v2 for full matrix support."`

**Why excluded**: Full matrix expansion interacts deeply with GoCD's fan-out/fan-in model, pipeline groups, and the dashboard. A naive 1→N expansion would create pipeline clutter. Proper expansion requires: (a) a visual grouping in the UI so matrix variants appear as a unit, (b) deduplication when re-syncing (don't orphan variants on matrix change), (c) the GoCD concept of "pipeline instances" already handles parameterized runs, so using that is more natural than N separate pipelines.

**v2 approach**: Use GoCD's parameterized pipelines. When a matrix is detected, store the matrix spec in pipeline `parameters`. The scheduler, when triggering the pipeline, expands the matrix into N pipeline instances, each with a unique combination of parameter values. This maps naturally to GoCD's `PipelineInstance` model (which already has a `counter` per pipeline+parameters). The dashboard would group instances by the base pipeline name.

**Migration impact**: None. v1-created pipelines with matrices would gain automatic matrix expansion in v2 without data migration — the matrix metadata is already stored.

---

#### 2. Custom GitHub Actions (`uses:` references to `actions/*`)

**What it is**: GH Actions workflows reference reusable actions like `actions/checkout@v4`, `actions/setup-node@v4`, `docker/login-action@v3`, etc. These are separate repositories containing `action.yml` definitions that can run Node.js, Docker, or composite steps.

**v1 behavior**: The parser identifies `uses:` steps and records them in the IR with type `"action"` and the action reference string. The translator skips these steps entirely during pipeline generation and emits a warning: `"Skipped action: actions/checkout@v4 — custom actions not supported in v1."` A skipped-actions count is included in the pipeline metadata.

The only exception: built-in checkout (material clone). GoCD's git material already checks out the repo, so the implicit `actions/checkout` step's effect is covered by the material definition. The translator detects this common case and doesn't warn for it.

**Why excluded**: Each action is a mini-program (Node.js Docker container with `action.yml`). Supporting them requires: (a) an action runtime (ability to pull and execute Docker images referenced in action definitions), (b) a marketplace resolver (map `actions/checkout@v4` to a specific git tag/hash), (c) input/output handling between actions, (d) secret resolution. This is essentially reimplementing a significant portion of the GitHub Actions runner. The `act` executor already handles this — so the recommended v1 path is "execute mode" for workflows with custom actions.

**v2 approach**: Two complementary strategies:
1. **Curated built-ins**: Identify the top ~20 most-used actions (`checkout`, `setup-node`, `setup-python`, `setup-go`, `cache`, `upload-artifact`, `download-artifact`, `docker/login`, `docker/build-push`, `configure-aws-credentials`, etc.) and map each to a combination of GoCD tasks + built-in operations. These become first-class translations.
2. **Action-as-task**: For the rest, provide a generic `"action"` task type that, when executed by an agent, uses the `act` runtime to execute just that single action in isolation. The agent would need `act` capability plus the action's Docker image available.

**Migration impact**: Pipelines with skipped actions would gain translated tasks in v2. The wizard should offer a "re-translate with v2 features" option on sync.

---

#### 3. GitLab CI `extends:` and YAML Anchors Beyond `!reference`

**What it is**: GitLab CI supports `.job_templates` with `extends:` where a job can inherit from one or more templates. This is distinct from YAML anchors (`&anchor` / `*alias`) — `extends:` does deep merge with specific rules for arrays and hashes. Nested `extends:` chains are common in enterprise GitLab configs (e.g., `.rules-template` → `.build-template` → `build-job`).

**v1 behavior**: 
- YAML anchors (`&` / `*`): Handled natively by the YAML parser (`yaml_elixir`), so these work automatically.
- `!reference` tags: Fully supported (Phase 1.3 covers this).
- `extends:` keyword: The parser detects `extends:` on a job definition and records the referenced template name. The job is parsed as-is (without merging the template's keys). A warning is emitted: `"extends: .build-template detected — template merging not supported in v1. Job may be incomplete."`
- Hidden keys (`.template_name`): Parsed and stored in IR as templates available for reference, but not translated into GoCD pipelines themselves.

**Why excluded**: Correct `extends:` merging is non-trivial. GitLab's merge rules differ from simple deep-merge: (a) hashes are deep-merged, (b) arrays are replaced (not concatenated), (c) `script` arrays merge with `before_script` going before, (d) some keys like `variables` are deep-merged with override semantics. Getting this wrong would silently misconfigure pipelines. Additionally, cross-file `extends:` (v1 supports full `include:`, but `extends:` across included files) adds dependency graph complexity.

**v2 approach**: Implement GitLab's exact merge algorithm. Reference: GitLab's own `gitlab` gem in Ruby or the community `gitlab-ci-merge` implementations. The merge logic should be extracted into `ExGoCD.ConfigRepos.GitLabCIMergeResolver` with exhaustive property-based tests comparing against GitLab's behavior. Cross-file resolution follows the `include:` graph already built in v1.

**Migration impact**: Pipelines translated in v1 with incomplete jobs (from unmerged extends) would need re-translation in v2. The wizard should detect `has_unresolved_extends: true` on old files and prompt for re-sync.

---

#### 4. Monorepo Subdirectory Scanning for GitLab CI

**What it is**: In monorepos, `.gitlab-ci.yml` files can exist in subdirectories (e.g., `services/api/.gitlab-ci.yml`, `services/web/.gitlab-ci.yml`). GitLab supports this with `include:local` from a root `.gitlab-ci.yml`, or by configuring the CI config path per project. Large monorepos may have dozens of CI configs.

**v1 behavior**: File discovery scans for:
- `.github/workflows/*.yml` at the repo root
- `.gitlab-ci.yml` at the repo root ONLY

Subdirectory `.gitlab-ci.yml` files are discovered ONLY if they are referenced via `include:local` from the root file, since include resolution is fully supported (Phase 1.3). Directly configured subdirectory paths (without root includes) are not discovered.

**Why excluded**: Monorepo support requires: (a) a configurable scan path (glob pattern or explicit list), (b) multiple pipelines sharing a single config repo (one `.gitlab-ci.yml` per subdirectory = one GoCD pipeline), (c) material path scoping (subdirectory trigger filters — only trigger the API pipeline when `services/api/**` changes), (d) parallel discovery performance (scanning deep directory trees). Without proper scoping, monorepo support would create noisy pipeline triggers.

**v2 approach**:
1. Add `scan_paths` (jsonb array of glob patterns) to `config_repos.configuration` — default `[".github/workflows/*.yml", ".gitlab-ci.yml"]`, configurable to `["services/*/.gitlab-ci.yml"]`.
2. Each discovered CI file becomes a separate pipeline, named after its subdirectory (e.g., `services-api` from `services/api/.gitlab-ci.yml`).
3. Material trigger scoping: the Git material for each pipeline gets a `destination` filter so it only triggers on changes under that subdirectory. This maps to GoCD's material `filter_include` field.
4. Dashboard grouping: all pipelines from the same monorepo share a pipeline group named after the config repo.

**Migration impact**: None for existing single-root repos. New `scan_paths` config is opt-in. Adding scan paths to an existing config repo would rediscover files — the wizard handles this naturally as "new files detected."

---

#### 5. Advanced Pipeline Group Mapping

**What it is**: GoCD organizes pipelines into named groups for dashboard organization. GitHub Actions has no equivalent concept. GitLab CI has no direct equivalent either, though folder-organized includes imply grouping.

**v1 behavior**: All pipelines translated from a config repo go into a single pipeline group named after the config repo itself (sanitized: repo name from URL, e.g., `my-org_my-repo`). This is simple and predictable. Within that group, GH Actions workflow files appear as separate pipelines (named after the workflow file). GitLab CI produces a single pipeline per root file; monorepo subdirectory files (in v2) each produce their own pipeline in the same group. The group name can be manually overridden in the wizard's Step 3.

**Why excluded**: This is intentionally minimal — it covers the 80% case (one config repo → one pipeline group) without introducing complexity. More advanced grouping (e.g., GH Actions environment → GoCD pipeline group, or label-based grouping) has unclear semantics and would need user input. It's better to ship the simple default first and learn from usage.

**v2 approach**: Enhance the wizard's Step 3 with a "Pipeline Group Template" field supporting:
- `${repo}` (default) — the repo name
- `${environment}` — GH Actions environment name
- `${path}` — file subdirectory (for monorepo mode)
- Custom string with those variables
- Per-file group override

**Migration impact**: v1 pipelines would stay in their original groups. Changing group assignments in v2 would be a manual operation via the wizard re-sync.

---

#### 6. Approval Gates from GH Environments / GitLab Environments

**What it is**: GitHub Actions has `environment:` with protection rules (required reviewers, wait timer, deployment branches). GitLab CI has `environment:` with similar concepts and also `when: manual` for approval gates.

**v1 behavior**: The parser records `environment:` metadata in the IR. The translator ignores it — no manual stages are created for environments. A warning is emitted: `"Environment 'production' with protection rules detected — approval gates not supported in v1."` All stages get `approval_type: "success"` (automatic).

GitLab CI `when: manual` jobs ARE handled in v1 — they translate to GoCD stages with `approval_type: "manual"`, because this is a direct concept match. The manual approval appears in the GoCD pipeline view as a stage that requires a user click to progress.

**Why excluded**: GH Environments protection rules are complex: they include required reviewers (individual users or teams), wait timers, deployment branch restrictions, and custom deployment payloads. Mapping this to GoCD requires: (a) GoCD's authorization model integration (map GitHub teams to GoCD roles), (b) a timer-before-approval stage type, (c) branch-gate validation at trigger time. GitLab's environment concept adds `on_stop` actions and environment URLs which don't have direct GoCD equivalents.

**v2 approach**:
- GH Environments: Map `environment.protection_rules.required_reviewers` to GoCD stage `approval_authorization` (roles/users). Map `wait_timer` to a new GoCD stage attribute `approval_delay_seconds` (a timer before the approve button becomes active).
- GitLab Environments: Map `environment.url` to the pipeline's `tracking_tool` or a new `environment_url` field. Map `on_stop` to an `on_cancel` task on the deployment stage.
- Both: The wizard should surface environment rules during import and allow overriding/confirming.

**Migration impact**: v1 pipelines with environments would gain approval gates on re-translation in v2. The wizard should clearly indicate when a re-sync will ADD approval gates (this is a functional change, not just a data migration).

---

### Summary: v1 Scope Boundary

| Feature Area | v1 Does | v1 Does NOT Do |
|---|---|---|
| **GH Actions triggers** | push, schedule, workflow_dispatch | pull_request (complex branch merging), workflow_call (sub-workflows) |
| **GH Actions jobs** | runs-on, env, steps (run:), needs, if | services, container, outputs, concurrency |
| **GH Actions steps** | run: → exec task | uses: → custom actions, with: → action inputs |
| **GitLab CI stages** | Full stage ordering | N/A |
| **GitLab CI jobs** | stage, script, needs, rules, variables, tags, artifacts, when:manual | image, services, retry, interruptible, resource_group, dast_configuration |
| **GitLab CI includes** | local, remote, project, template + !reference | extends: (template merging) |
| **File discovery** | Root `.github/workflows/` + root `.gitlab-ci.yml` | Subdirectory scanning, glob patterns |
| **Execution** | act (GH), gitlab-runner exec (GL) via agent capabilities | Custom action execution, act environment setup |
| **Elastic agents** | Docker + K8s provisioning, cleanup | Autoscaling, spot instance support, multi-cloud |
