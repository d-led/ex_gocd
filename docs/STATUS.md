# ex_gocd — Verified Status

> Measured 2026-11-01 on `main`. Every number below was produced in this working
> tree, not copied from an earlier doc. Reproduce with the commands in each
> section.
>
> `PARITY.md` was last audited 2026-07-08 and its headline claims are stale —
> see [Doc drift](#doc-drift). Treat this file as the current source of truth.

---

## Where we are, in one table

| Dimension | State | Evidence |
| --- | --- | --- |
| Code | 275 modules, compile warnings-as-errors clean | `mix compile --force --warnings-as-errors` |
| ExUnit | **1101 tests, all green** | `mix test` |
| Coverage | **55.2 %** of 274 modules; 78 at 0 % | `mix test.coverage` |
| Go agent | builds; tests pass in 3 of 10 packages (3,793 prod LOC / 599 test LOC); modules upgraded 2026-11-01 (otel 1.47, grpc 1.85) | `cd agent && go test ./...` |
| Cypress | 27 specs on disk, **not executed in this session** | `ls cypress/e2e/*.cy.js` |
| Static analysis | `scripts/quality-gate.sh` passes as a whole: 17 steps, 0 failures (format, compile, Sobelow, credo, doc references, test database, ExUnit, Go fmt/vet/golangci-lint/tests/gofmt/mod-tidy, jscpd, ESLint, TypeScript, Prettier, link checker). Two findings are kept and documented rather than ignored: the MD5 artifact checksums, which are the format a GoCD agent writes. `mix dialyzer` was run for the first time on 2026-11-02: 41 warnings remain, concentrated in `pipelines.ex` (8), `scheduler.ex` (8), `agent_channel.ex` (6) and `materials/scm_client.ex` (4), of kinds `call` (18), `no_return` (12), `pattern_match` (5), `guard_fail` (5) and `invalid_contract` (1). Three stale specs it found are fixed: two modules were referenced as `.t()` without defining one, and `material_filter`'s spec named an unaliased `Material`. `staticcheck` cannot serve either, its binary being older than the Go toolchain, and the gate now says that instead of blaming the code | see above |
| CI | every commit through `ae8b54c` is green on Elixir CI, CodeQL and Sobelow, and two of those runs show the documentation check executing and printing `[PASS] documentation references resolve` in the `build` job. `5d74c99` and `8331faf` were still queued at hand-off; both pass the whole local gate | `gh run list` |
| Security | **0 open Dependabot alerts**; `npm audit` 0 vulnerabilities | see above |
| Dependencies | Hex and npm on their latest releases; Go modules not yet | `mix hex.outdated`, `npm outdated` |
| Upstream | pulled to `gocd/gocd` `eb504a6a6b`; `api.go.cd` has no `source/` changes | see [Upstream delta](#upstream-delta) |

The suite being green and the coverage being half the code are both true at
once. Green
means nothing currently *fails*; it does not mean the untested paths work.

---

## How testing is set up

### Layers

| Layer | Command | Needs Postgres | Runs in CI |
| --- | --- | --- | --- |
| ExUnit | `mix test` | yes, already prepared | yes |
| ExUnit, no database | `EX_GOCD_TEST_NO_DB=1 mix test` | no | no |
| Coverage | `mix test.coverage` (Coveralls JSON) | yes, already prepared | no |
| Go agent | `cd agent && go test ./...` | no | yes |
| Cypress | `bash scripts/run_cypress.sh` | yes (server + agent) | separate workflow |
| Everything static | `bash scripts/quality-gate.sh` | yes (runs `mix test` itself) | no |

`mix test` does **not** create or migrate the database. That race on
`CREATE DATABASE` is what made two concurrent runs collide. Prepare once:

```bash
mix test.setup
```

`test_helper.exs` checks that the schema is there and fails with that
instruction rather than a connection error.

### Sandbox

The sandbox runs in `:manual` mode. A synchronous test switches the pool into
shared mode, so every process the application started can reach its connection.
An async test owns a connection for itself alone: lending it to a shared
GenServer makes two writers queue on one connection, which is how a request got
dropped after 560 ms in an intermittent failure. The rule that follows is one
sentence — **a test that drives a shared GenServer runs synchronously.**

Anything a test writes is rolled back with it, so tests do their own setup and
never clean up afterwards.

Workers that would query on their own timer — `StartupReaper`,
`ConfigRepos.Poller` — are switched off in `config/test.exs`, because their work
would happen outside any transaction. Tests call the functions directly.

A test that drives a singleton must run `async: false`: a shared GenServer can
only belong to one connection at a time, and two async owners would take it from
each other. Nine test modules do this.

### Pointing the suite at a database

`config/test.exs` honours `DATABASE_URL` first (that is what CI provides), then
`PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD` with `localhost:5432` as the default. To
keep this project off a port another project owns:

```bash
docker rm -f gocd-rewrite-test-db
docker run -d --name gocd-rewrite-test-db -p 5544:5432 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=postgres postgres:18-alpine
PGHOST=127.0.0.1 PGPORT=5544 mix test.setup
PGHOST=127.0.0.1 PGPORT=5544 mix test
```

Two suites can now run at the same time against the same database.

`elixir scripts/check_test_db.exs` says whether that database is reachable
before anything tries to use it, and it runs as a step in
`scripts/quality-gate.sh`: a stopped container used to look like a failing test
suite. It warns when the resolved port is the default 5432, because that is
usually another project's PostgreSQL and `mix test.setup` would create this
project's schema inside it.

When Docker is not available, the Homebrew PostgreSQL 18 serves the same purpose
on the same port, in a throw-away directory:

```bash
export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
initdb -D /tmp/ex_gocd_pg18 -U postgres --auth=trust
pg_ctl -D /tmp/ex_gocd_pg18 -o "-p 5544 -k /tmp/ex_gocd_pg18 -h 127.0.0.1" \
  -l /tmp/ex_gocd_pg18.log start
PGHOST=127.0.0.1 PGPORT=5544 mix test.setup && PGHOST=127.0.0.1 PGPORT=5544 mix test
```

The suite has run green against one (2026-11-02), which also shows
the migrations apply to an empty database rather than only incrementally.

### What the suite does not reach

79 modules never execute. The ones that carry real features rather than
boilerplate:

| Module | Uncovered lines | Notes |
| --- | --- | --- |
| `live/analytics_live.ex` | 269 at 41.6 % | The tabs are tested through the page, including two with a run behind them; `analytics.ex` itself is at 87.4 % |
| `live/admin_k8s_live.ex` | 239 | Feature is claimed complete in `PARITY.md` |
| `live/external_ci_repo_wizard_live.ex` | 230 | ditto |
| `live/gantt_live.ex` | 123 | |
| `docker.ex` | 99 | |
| `live/audit_log_live.ex` | 77 | |
| `live/config_diff_live.ex` | 53 | |
| `controllers/config_xml_controller.ex` | 20 | Legacy `/admin/config_xml` export/import/revert UI |
| `elastic_agent_scheduler.ex` | 186 at 12.9 % | Its tick decides when to create and delete pods, and every one of those decisions calls Kubernetes directly, with no seam to stand in for it. Testing the tick needs that seam first — a behaviour for the pod calls, injected — which is a design decision rather than a test |
| `channels/*` (5 files, 412 lines) | covered by `test/ex_gocd_web/channels/` | see [the agent WebSocket tree](#the-agent-websocket-tree-is-not-dead-code-it-was-untested) |

`config_xml_test.exs` covers `generate/0` and `import_from_xml/1`, including a
generate → `from_xml/1` round trip and an idempotent second import.
`config_repos/parser_test.exs` covers the GoCD-format config repo parser, and
`feeds_controller_test.exs` the Atom feeds. `config_xml_controller_test.exs`
covers the revert itself: that it restores a secret config, which only the JSON
holds, and that it refuses a version with no stored XML.

---

## Known gaps

### Config XML export covers part of the configuration, and revert no longer loses the rest

`generate/0` renders pipelines, templates, environments, roles, cluster profiles,
elastic agent profiles and config repos, and `import_from_xml/1` stores them
again — cluster profiles round-trip with their secrets encrypted in the document
and the agent profiles that reference them resolved by name.

It does **not** render artifact stores, secret configs, package repositories or
SCMs. Those property bags are plugin-defined: which entry is a credential is
only known from plugin config metadata, and this build reads none, so the
export cannot tell a registry URL from a password. Guessing would either leak a
credential into version history — which the API serves — or encrypt something a
plugin has to read back.

A revert therefore reads both artefacts of a version: the XML through
`ConfigXml.import_from_xml/1`, then `ConfigRestore.restore/1` for the four
sections only the JSON holds. Each of those is upserted on the key its schema
keeps unique (artifact store id, secret config and package repository name,
config repo url and source type), so a restore adds and updates but never
deletes. The restore runs in one transaction and through each schema's
changeset, so a version that cannot be restored in full leaves nothing
half-restored and the revert says which half happened. Nothing is dropped on a
revert any more; the XML is still short of those four sections as an interop
artefact.

Config repos are exported as `<config-repos>`, and the pipelines that belong to
one are left out of `<pipelines>`. Both halves follow upstream: `configRepos` is
a `@ConfigSubtag` of `BasicCruiseConfig`, so `<config-repos>` is part of
`cruise-config.xml`; and `MagicalGoConfigXmlWriter.write/3` refuses a config that
is not local (`"Attempted to save merged configuration with partials"`), because
config-repo pipelines are merged into the groups in memory only. Writing them
into the document would turn a pipeline a repository tracks into a hand-written
one that no longer follows its repository. `Pipeline.config_repo_id` is what
tells the two apart.

### Fixed: five capture sections were silently empty

Every section of `config_json` is built by `safe_section/1`, which records a
section that raises as `{"_error" => …}` instead of failing the snapshot. Each
of these sections also had its own `rescue _ -> []`, so a broken section looked
identical to an empty one. `templates`, `secret_configs`,
`package_repositories` and `config_repos` were all broken and all silent:

| Section | Cause |
| --- | --- |
| `templates` | aliased `PipelineTemplate`; the module is `ExGoCD.Pipelines.Template` |
| `secret_configs` | read `encrypted_value` and `properties`; the schema has `configuration` and `description` |
| `package_repositories` | aliased `ExGoCD.Packages.PackageRepository`; the module is under `PackageRepositories`, and the schema has `configuration`, not `repo_url`/`properties` |
| `config_repos` | read `repo_url`, `password` and `material_update_interval`; the schema has `url`, `branch`, `material_type`, `source_type`, `configuration` |

So no version ever captured a template, a secret config, a package repository or
a config repo. The inner rescues are gone; `safe_section/1` already reports a
broken section, and the snapshot test now asserts that no section reports
`_error`. `scms` still returns `[]` because this build has no SCM table — a
repository is named by the material that points at it.

### Fixed: two 0 %-coverage pages were hiding four faults

Writing the first tests for the admin K8s page and the external CI wizard found
four faults that nothing had exercised, because both pages render fine until
someone submits a form:

| Page | Fault |
| --- | --- |
| K8s | a field error was rendered with `{for err <- form[:field].errors, do: err}`, and an error is a `{message, opts}` pair, so a missing name raised and took the form down |
| K8s | the guard was `:if={errors}`, and an empty list is truthy, so the red box drew with nothing in it |
| Wizard | each file was stored with the repository's kind (`github_actions`) as its own `source_type`, which the file schema rejects, so the last step could never be saved |
| Wizard | `selected_jobs`/`selected_triggers` are lists and the columns were jsonb, so the selection was rejected as well; the inserts matched `{:ok, _}`, so the rejection crashed the page rather than reporting |

The wizard's two columns are `text[]` now (migration
`20261101230000_config_repo_file_selection_stores_lists`).

Writing the first analytics page tests found a fifth: the pipeline detail tab
rendered runs, pass rate, MTTR and build time under no heading, so a person
following a link to it could not tell which pipeline they were reading. It names
the pipeline now.

A sixth came from the first dialyzer run: it flagged a branch in the stage
notification mapping that could never run. Following it showed the whole path was
mute. Filters are stored lowercase (`fails`, `passes`) and the completion path
dispatched `Fails`/`Passes`, so **no stage notification ever matched a filter** —
only a filter set to "all" received anything. Cancellation dispatched nothing at
all, and `cancelled` was not even in the list of events a filter could be created
with. Both are fixed, with three tests that watch the mail.

### Known noise: the sandbox says a connection was disconnected

Most runs print one or two lines like

    Postgrex.Protocol (…) disconnected: ** (DBConnection.ConnectionError)
    #PID<…> (:erlang) checked in the connection owned by #PID<…> (ExGoCD.Scheduler)

They come from sandbox teardown and appear in every file, async or not, whether
the suite passes or not: `test/ex_gocd/analytics_pipelines_test.exs` alone prints
one, `test/ex_gocd/test_agent_test.exs` alone prints two. Nothing fails because
of them, and the Scheduler keeps working. They are recorded here so that a later
reader does not take them for the regression they look like.

### Doc drift
`docs/PARITY.md` now opens by saying it is a map of intent rather than a status
report, and it carries no counts: the ones it had were 1004 tests, 67
controllers, 23 LiveView pages, 20 GenServers, 42 migrations and 22 Cypress
specs, all measured 2026-07-08 and all stale. Its claim that the Go agent speaks
WebSocket was wrong, in the stack table, the topology diagram and the feature
table: the agent speaks HTTP remoting, like a real GoCD agent
(`agent/internal/remoting/`, `agent_remoting_controller.ex`, and no `websocket`
string anywhere in the Go agent).

`README.md` badges are hand-written and say 1101 tests and 27 Cypress specs.
Nothing regenerates them, so they will drift again.

`scripts/check_doc_refs.exs` is the part that cannot drift: it fails when a
source file, an `/api` route, an Elixir module named in `module_mapping.md` or an
internal link stops existing. It runs as a step in `scripts/quality-gate.sh` and
in the `build` job of `.github/workflows/elixir.yml`, so a rename that leaves a
doc behind now fails CI. All 36 references the feature table made resolved when
it was added (2026-11-02), and so did every module the mapping names. It checks
that the things a claim points at exist, not that the claim is true; that is the
coverage table above.

### The agent WebSocket tree is not dead code — it was untested

`lib/ex_gocd_web/channels/` was called dead code here. It is not: two things use
it, and neither had a test.

- `AgentSocket` and `AgentChannel` carry `ExGoCD.HTTPTestAgent`, which
  `POST /api/test/agents/http` starts in test mode and in dev, so a simulated
  agent can drive the protocol over raw TCP. The shipped Go agent speaks HTTP
  remoting instead — `agent/internal/remoting/`, `agent_remoting_controller.ex`.
- `UserSocket` and `AgentsChannel` carry the dashboard's `agents:updates`
  subscription, which `assets/js/app.js` opens so the agent list refreshes.

Both have tests now (`test/ex_gocd_web/channels/`). They found that
`AgentsChannel` had no clause for a message it did not recognise, so anything
else published on that topic took the channel down and live updates stopped
until the page was reloaded. It ignores unknown messages now.

`AgentChannel` still has no catch-all: an agent speaks an enumerated protocol,
and an unexpected message there should be loud rather than silently dropped.

---

## Upstream delta

`gocd/gocd` is pulled to `eb504a6a6b` (132 commits past the previous checkout).
Almost all are dependency bumps. The subset that touches behaviour, and what it
means for us:

| Commit | Change | Status here |
| --- | --- | --- |
| `cfc94e215b` | config-repo partials are no longer removed when an SCM revision did not change; validity is compared by structure as well as origin | **Implemented in spirit.** We never removed incorrectly, because we never removed; a config repo now replaces the pipelines it declares, but only after a parse that produced pipelines — see `ConfigRepos.Parser.remove_undeclared/2` |
| `a54f70ea90` | the Git branch field moves next to "Repository URL", out of Advanced Settings | **Not applicable.** Our material form is LiveView and has no Advanced Settings split |
| `5439afc917` | the agent resources checklist is sorted case-insensitively | **Not applicable.** Our agents page shows resources as a joined string, not a checklist |

`gocd/api.go.cd`: 4 commits behind, **all dependency bumps, zero changes under
`source/`**. The published API spec we target is unchanged.

Go modules in `agent/` have newer versions available (`go list -m -u all`); they
were left alone because they sit under the Kubernetes client.

---

## Decisions carried forward

Reconstructed from the two indexed sessions for this workspace
(`8a5a40eb…`, `33121644…`); the memory palace holds no `ex_gocd` wing.

| # | Decision | Why |
| --- | --- | --- |
| D1 | Test Postgres runs in Docker; **never** a host-installed Postgres | Explicit instruction, 2026-09-11 |
| D2 | Agent speaks GoCD's **HTTP remoting** protocol, not WebSocket | To be a drop-in replacement for the Java agent |
| D3 | Admin CRUD is served under **both** `/api/admin/*` and `/go/api/admin/*` | GoCD compatibility (`c5d0098`) |
| D4 | LiveViews stop silently falling back to mock data | Fake data hides breakage (`d380037`) |
| D5 | No fake or placeholder implementations; gaps get fixed or recorded as deferred | Session premise |
| D6 | Templates and elastic-agent profiles resolve by name *or* id | GoCD accepts both (`0466cbb`) |
| D7 | Fixture timestamps anchor to the present | Avoid time-bomb tests (`fec5e0f`) |
| D8 | Every test owns its sandbox connection; background workers that query on a timer stay off in test | Sandbox refactor, 2026-11-01 |
| D9 | Dependencies track the latest Hex and npm releases rather than a pinned baseline | Explicit instruction, 2026-11-01 |
| D10 | A config repo owns the pipelines it declares: a parse that produced pipelines replaces them; a failed or empty parse keeps the last good config | Correctness, and the invariant behind upstream `cfc94e215b`, 2026-11-01 |
| D11 | A test that drives a shared GenServer runs synchronously; an async test owns a connection for itself only | Removes a real queue-contention flake, 2026-11-01 |
| D12 | A material's identity is (type, url, branch): same repository and branch is one poll, a different branch is a different material | Two pipelines on different branches silently overwrote each other, 2026-11-01 |
| D13 | Background work that queries on its own schedule stays off in tests, and a config snapshot runs inside the caller rather than in a detached task | Work outside the test's transaction cannot be asserted on, and hides its own failures, 2026-11-01 |

---

## Proposed next steps

1. ~~**Make a revert restore everything.**~~ Done: the revert reads the XML and
   then `ConfigRestore` for the four sections only the JSON holds.
2. **Re-audit the rest of `PARITY.md` against the code.** Its header, counts and
   agent-transport claim are fixed and it no longer claims parity; what remains
   is the per-feature table, which still says "✅" without a verification.
3. ~~**Delete or declare `lib/ex_gocd_web/channels/`.**~~ Declared, and it turned
   out to be live rather than dead; both trees have tests now.
4. ~~**Close the largest untested features**~~ Two of the three are done: the
   admin K8s page (57.8 %) and the external CI wizard (63.6 %), which turned up
   four faults in the code they now cover. The analytics tabs' data paths are
   still untested.
5. ~~**Upgrade the Go modules** in `agent/`~~ Done: `go get -u ./...`, then
   build, vet and test clean.
6. **Teach the XML the four plugin sections** if an external reader ever needs
   them, which first needs a way to know which plugin property is a secret.
