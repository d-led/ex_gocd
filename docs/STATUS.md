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
| ExUnit | **1032 tests, all green**, 8.6 s | `mix test` |
| Coverage | last measured at **49.5 %** of 274 modules; 87 at 0 % | `mix test.coverage` |
| Go agent | builds; tests pass in 3 of 10 packages (3,793 prod LOC / 599 test LOC) | `cd agent && go test ./...` |
| Cypress | 27 specs on disk, **not executed in this session** | `ls cypress/e2e/*.cy.js` |
| Static analysis | `mix format --check-formatted` clean; `mix credo --strict` exit 0 (3 readability notes) | see above |
| CI | last `main` push 2026-09-13: Elixir CI, CodeQL, Sobelow all green | `gh run list` |
| Security | **0 open Dependabot alerts**; `npm audit` 0 vulnerabilities | see above |
| Dependencies | Hex and npm on their latest releases; Go modules not yet | `mix hex.outdated`, `npm outdated` |
| Upstream | pulled to `gocd/gocd` `eb504a6a6b`; `api.go.cd` has no `source/` changes | see [Upstream delta](#upstream-delta) |

The suite being green and the coverage being 49.5 % are both true at once. Green
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

The sandbox runs in `:manual` mode. `ExGoCD.DataCase.setup_sandbox/1` checks out
a connection per test and returns the owner; `ExGoCD.Sandbox` lends that
connection to the application's long-lived singletons from one list. Anything a
test writes is rolled back with it, so tests do their own setup and never clean
up afterwards.

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

### What the suite does not reach

87 modules never execute. The ones that carry real features rather than
boilerplate:

| Module | Uncovered lines | Notes |
| --- | --- | --- |
| `live/analytics_live.ex` | 268 | Feature is claimed complete in `PARITY.md` |
| `live/admin_k8s_live.ex` | 239 | ditto |
| `live/external_ci_repo_wizard_live.ex` | 230 | ditto |
| `controllers/feeds_controller.ex` | 146 | CCTray/Atom feeds, routed at `/go/cctray.xml`, no e2e |
| `live/gantt_live.ex` | 123 | |
| `docker.ex` | 99 | |
| `live/audit_log_live.ex` | 77 | |
| `live/config_diff_live.ex` | 53 | |
| `controllers/config_xml_controller.ex` | 20 | Legacy `/admin/config_xml` export/import/revert UI |
| `elastic_agent_scheduler.ex` | 186 at 12.9 % | |
| `channels/*` (5 files, 412 lines) | ~0 % | see [Dead code](#dead-code-agent-websocket-channels) |

`config_xml_test.exs` now covers `generate/0` with materials, including a
generate → `from_xml/1` round trip. `import_from_xml/1` is still untested, and
that is where the next bug is — see [Config XML import](#config-xml-import-does-not-persist-the-config).

---

## Known gaps

### Config XML import does not persist the config

`import_from_xml/1` parses materials and stages and then drops them:
`Pipeline.changeset/2` casts neither, so an imported pipeline is an empty shell.
Export is correct and covered; import is not.

### Config repos never prune

Nothing removes a pipeline when a config repo stops declaring it. GoCD keeps a
config repo's partials and replaces them wholesale on a successful parse; we only
ever upsert. Upstream `cfc94e215b` guards the opposite mistake — a re-parse that
does not change the SCM revision must not drop valid partials — but the
invariant worth copying is: prune only after a parse that succeeded, never on
failure.

The GoCD-format config repo parser (`ConfigRepos.Parser.parse_and_upsert/2`) has
no test file; only the GitHub Actions and GitLab CI parsers do.

### Doc drift

`docs/PARITY.md` header, verified value in brackets:

| Claim | Reality |
| --- | --- |
| "100 % feature parity, all gaps resolved" | contradicted by the gaps above and the 87 zero-coverage modules |
| 1004 tests [1032] | |
| 67 controllers [61] | |
| 23 LiveView pages [22] | |
| 20 GenServers [22] | |
| 42 migrations [44] | |
| 22 Cypress specs [27] | |
| Agent transport "WebSocket" | HTTP remoting — `agent/internal/remoting/`, `agent_remoting_controller.ex`; zero `websocket` strings in the Go agent |

`README.md` badges claim 949 tests and 16 Cypress specs.

### Dead code: agent WebSocket channels

`lib/ex_gocd_web/channels/` is 412 lines at ~0 % coverage, and the Go agent has
no WebSocket client. `endpoint.ex` still mounts `ExGoCDWeb.AgentSocket` at
`/agent-websocket` and `ExGoCDWeb.UserSocket` at `/socket`, so the tree is
reachable but nothing in the shipped system uses it. Either delete it or state
plainly that it is a compatibility surface.

---

## Upstream delta

`gocd/gocd` is pulled to `eb504a6a6b` (132 commits past the previous checkout).
Almost all are dependency bumps. The subset that touches behaviour, and what it
means for us:

| Commit | Change | Status here |
| --- | --- | --- |
| `cfc94e215b` | config-repo partials are no longer removed when an SCM revision did not change; validity is compared by structure as well as origin | **Not applicable as written.** We never remove, so we cannot remove incorrectly — see [Config repos never prune](#config-repos-never-prune) for the invariant worth taking |
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

---

## Proposed next steps

1. **Make config XML import persist materials and stages**, with tests on
   `import_from_xml/1` and a generate → import → generate round trip.
2. **Prune config-repo pipelines** on a successful parse, guarded as upstream
   guards it. Write the missing `Parser` test file first.
3. **Re-audit `PARITY.md` against the code** rather than against the previous
   audit. Replace the "100 %" claim with the verified coverage table, or split
   the file into "claimed" and "verified" columns.
4. **Delete or declare `lib/ex_gocd_web/channels/`.** 412 lines that nothing
   exercises.
5. **Close the largest untested features**: the three 0 %-coverage LiveViews and
   the CCTray feeds. Feeds are cheap and externally visible — they belong in the
   suite before the LiveViews.
6. **Upgrade the Go modules** in `agent/`.
