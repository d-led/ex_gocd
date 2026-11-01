# ex_gocd — Verified Status

> Measured 2026-11-01 on `main` @ `d957b7b`. Every number below was produced in
> this working tree, not copied from an earlier doc. Reproduce with the commands
> in each section.
>
> `PARITY.md` was last audited 2026-07-08 and its headline claims are stale —
> see [Drift](#doc-drift). Treat this file as the current source of truth.

---

## Where we are, in one table

| Dimension | State | Evidence |
| --- | --- | --- |
| Code | 277 modules, 411 files analysed by Credo | `mix credo --strict` |
| ExUnit | **1029 tests, all green**, 125 files, 18,643 lines, 36 s | `mix test` |
| Coverage | **49.5 %** total; 87 of 274 modules at 0 %; 121 under 50 % | `mix test.coverage` |
| Go agent | builds; tests pass in 3 of 10 packages (3,793 prod LOC / 599 test LOC) | `cd agent && go test ./...` |
| Cypress | 27 specs on disk, **not executed in this session** | `ls cypress/e2e/*.cy.js` |
| Static analysis | `mix format --check-formatted` clean; `mix credo --strict` exit 0 (3 readability notes) | see above |
| CI | last `main` push 2026-09-13: Elixir CI, CodeQL, Sobelow all green | `gh run list` |
| Security | **0 open Dependabot alerts** | `gh api .../dependabot/alerts?state=open` |
| Upstream | 132 commits behind `gocd/gocd`, 1 behaviour change that matters | see [Upstream delta](#upstream-delta) |

The suite being green and the coverage being 49.5 % are both true at once. Green
means nothing currently *fails*; it does not mean the untested paths work. One of
them demonstrably does not — see [Bug 1](#bug-1--config-xml-export-raises-on-any-material).

---

## How testing is set up

### Layers

| Layer | Command | Needs Postgres | Runs in CI |
| --- | --- | --- | --- |
| ExUnit | `mix test` | yes (creates + migrates) | yes |
| ExUnit, no DB prep | `mix test.no_db` / `mix test_no_db` | yes, must already exist | no |
| ExUnit, no DB at all | `EX_GOCD_TEST_NO_DB=1 mix test_no_db <path>` | no | no |
| Coverage | `mix test.coverage` (Coveralls JSON) | yes | no |
| Go agent | `cd agent && go test ./...` | no | yes |
| Cypress | `bash scripts/run_cypress.sh` | yes (server + agent) | separate workflow |
| Everything static | `bash scripts/quality-gate.sh` | yes (runs `mix test` itself) | no |

### Pointing the suite at a database

`config/test.exs` reads `PGHOST` / `PGPORT`, defaulting to `localhost:5432` to
match CI. Use it to keep this project off a port another project of yours owns:

```bash
docker rm -f gocd-rewrite-test-db
docker run -d --name gocd-rewrite-test-db -p 5544:5432 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=postgres postgres:18-alpine
PGHOST=127.0.0.1 PGPORT=5544 mix test
```

`scripts/quality-gate.sh` files that it does not read this variable — it calls
plain `mix test`.

### Two known rough edges in the test tooling

1. **`mix test` is not safe to run twice concurrently.** The `test` alias expands
   to `test.with_db`, which runs `ecto.create` every time. Two overlapping
   invocations race and one dies with
   `ERROR 23505 ... Key (datname)=(ex_gocd_test) already exists`. Not a data
   problem — drop the DB and re-run. Worth making `ecto.create` idempotent.
2. **`EX_GOCD_TEST_NO_DB=1` does not skip DB tests, it breaks them.** The flag
   stops `ExGoCD.Repo` from starting (`lib/ex_gocd/application.ex:10`), so all
   876 DB-backed tests fail with *"could not lookup Ecto repo"* rather than being
   excluded. The flag is only usable with an explicit file path. Either tag the
   DB tests and exclude them, or rename the flag to say what it does.
3. CI passes `DATABASE_URL` to `mix test`, but `config/runtime.exs` only reads
   `DATABASE_URL` under `config_env() == :prod`. The variable is inert; the
   defaults in `config/test.exs` are what actually match the service container.

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
| `controllers/config_xml_controller.ex` | 20 | Legacy `/admin/config_xml` export/import/revert UI. The API twin has a single empty-config test, see Bug 1 |
| `elastic_agent_scheduler.ex` | 186 at 12.9 % | |
| `channels/*` (5 files, 412 lines) | ~0 % | see [Dead code](#dead-code-agent-websocket-channels) |

`config_xml_test.exs` tests `from_xml/1` (parsing) only. `ConfigXml.generate/0`
(rendering) is never called with a non-empty config: `config_snapshot_test.exs`
drives it through `ConfigSnapshot.snapshot/2` with no pipelines, and the one
controller test asserts against an empty config. That is the gap Bug 1 lives in.

---

## Findings

### Bug 1 — config XML export raises on any material

`lib/ex_gocd/config_xml.ex:94` (and the `svn`/`hg`/`p4`/`tfs`/`dependency`
clauses) read `mat.name`, but `ExGoCD.Pipelines.Material` has no `:name` field —
it has `:destination`.

Proven by the current suite, which logs it while staying green:

```
** (KeyError) key :name not found in:
    %ExGoCD.Pipelines.Material{id: 104, type: "git", url: "git@github.com:test/repo.git", ...}
    (ex_gocd 0.1.0) lib/ex_gocd/config_xml.ex:94: ExGoCD.ConfigXml.render_material/1
    (ex_gocd 0.1.0) lib/ex_gocd/config_snapshot.ex:35: ExGoCD.ConfigSnapshot.snapshot/2
```

Reachable from `GET /api/admin/config.xml`, `GET /go/api/admin/config.xml` and
every pipeline mutation (`pipelines.ex` calls `ConfigSnapshot.after_mutation`
on create/update/delete). Because snapshots run in a detached `Task`, each of
those failures is swallowed into a log line — so config XML export and config
version history are both broken for any pipeline that has a material, and
nothing reports it.

### Doc drift

`docs/PARITY.md` header, verified value in brackets:

| Claim | Reality |
| --- | --- |
| "100 % feature parity, all gaps resolved" | contradicted by Bug 1 and the 87 zero-coverage modules |
| 1004 tests [1029] | |
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

`gocd/gocd` `HEAD..origin/master` = 132 commits as of this audit. Almost all are
dependency bumps. The subset that touches behaviour:

| Commit | Change | Bearing on us |
| --- | --- | --- |
| `cfc94e215b` | config-repo partials: a config-repo change that does not change the SCM revision no longer removes partials; `PartialConfigService.merge` argument order changed to `(fingerprint, partialConfig, config)` | **Only real one.** Check `config_repos/poller.ex` and any partial-merge logic |
| `a54f70ea90` | git material shows the branch next to the repository URL | `materials_live.ex` / dashboard |
| `5439afc917` | agent resources filter sorts case-insensitively | `agents_live.ex` |

`gocd/api.go.cd`: 4 commits behind, **all dependency bumps, zero changes under
`source/`**. The published API spec we target is unchanged.

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

---

## Proposed next steps

Ordered by "does this change what we can claim", not by effort.

1. **Fix Bug 1 and pin it with a test.** `ConfigXml.generate/0` for a pipeline
   with a git material must return XML, asserted through the HTTP endpoint.
   Nothing else on this list is honest until the export/version history path
   works.
2. **Re-audit `PARITY.md` against the code** rather than against the previous
   audit. Replace the "100 %" claim with the verified coverage table, or split
   the file into "claimed" and "verified" columns.
3. **Delete or declare `lib/ex_gocd_web/channels/`.** 412 lines that nothing
   exercises.
4. **Close the largest untested features**: the three 0 %-coverage LiveViews and
   the CCTray feeds. Feeds are cheap and externally visible — they belong in the
   suite before the LiveViews.
5. **Make the test alias idempotent** so two runs cannot collide on
   `ecto.create`, and make `EX_GOCD_TEST_NO_DB` mean "exclude DB tests" instead
   of "start nothing".
6. **Apply upstream `cfc94e215b`** to the config-repo poller path.
