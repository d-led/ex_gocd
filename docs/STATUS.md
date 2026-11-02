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
| Code | 268 source files, compile warnings-as-errors clean | `git ls-files 'lib/**/*.ex'` |
| ExUnit | **1243 tests, all green** | `mix test` |
| Coverage | **62.5 %**; 29 modules at 0 % | `mix test.coverage` |
| Go agent | builds; tests pass in 3 of 10 packages (3,793 prod LOC / 599 test LOC); modules upgraded 2026-11-01 (otel 1.47, grpc 1.85) | `cd agent && go test ./...` |
| Cypress | 27 specs on disk, **not executed in this session** | `ls cypress/e2e/*.cy.js` |
| Static analysis | `scripts/quality-gate.sh` passes as a whole: 17 steps, 0 failures (format, compile, Sobelow, credo, doc references, test database, ExUnit, Go fmt/vet/golangci-lint/tests/gofmt/mod-tidy, jscpd, ESLint, TypeScript, Prettier, link checker). Two findings are kept and documented rather than ignored: the MD5 artifact checksums, which are the format a GoCD agent writes. `mix dialyzer` was run for the first time on 2026-11-02: 41 warnings then, 6 now. Six that went were dead branches that hid real faults, described below; eighteen were calls `VsmTracer.set_status` made to a one-argument form whose spec wants a status record, which now go through the documented `set_status(code, message)`; the rest were stale specs and one function with no callers. The six that remain are named rather than silenced: `k8s.ex:136`, a third-party inference about `K8s.Client.run/2` inside the `Task` that probes a cluster (the probe cannot be driven from a test because the fake provider is registered per process); `test_report.ex:107` and `:109`, Ecto changeset typing in the store path that `parse_and_store/2` tests exercise on three report formats; `materials/scm_client.ex:140`, `:141` and `:151`, an `author || "svn"` whose producer always supplies a binary. Three stale specs it found early are fixed too: two modules were referenced as `.t()` without defining one, and `material_filter`'s spec named an unaliased `Material`. `staticcheck` cannot serve either, its binary being older than the Go toolchain, and the gate now says that instead of blaming the code | see above |
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

A seventh also came from dialyzer. `create_pod` and `delete_pod` were written to
treat "it is already there" and "it is already gone" as the answer they were
asked for, which is what makes a retried provisioning pass harmless. The branches
that recognised those answers matched `reason: "AlreadyExists"` as an atom.
`K8s.Client.APIError` carries the reason as a string, so neither branch could
match: asking for a pod that existed returned an error, as did asking for one to
be deleted when it was already gone. The Kubernetes agent's whole lifecycle
worker therefore error-looped on its own retries. Fixed, with three tests that
stand a fake HTTP provider behind the connection — a pod that exists counts as
created, a pod that is gone counts as deleted, and any other refusal is still a
failure.

An eighth also came from dialyzer, and is the same family as the sixth: two
components disagreeing about a name. The scheduler asked its agent-selector
plugin for `select_agent/3`; the behaviour declares `select_candidates/3`. The
call therefore raised `:undef`, a `rescue _ -> true` swallowed it, and every
clause of the case that read the answer returned `true` anyway — so a plugin's
veto never took effect and the plugin could not have had one. The scheduler now
calls the declared callback and honours `{:ok, agents}` and `{:reject, reason}`;
a plugin that crashes is logged and the agent is allowed, because a broken policy
must not stop the queue. Three tests watch an agent take the job, leave it queued,
and take it when the selector fails. The registry's `node_for/1` spec said
`String.t()` while the code stored a node atom, and the broadcast registration
path stored a string — both now yield a node, which is what a remote call needs.

A ninth: the JSON log backend, whose lines Fluent Bit forwards to Loki, matched
the current span context against an eleven-element tuple. The record OTel
defines has thirteen fields, so the pattern never matched and **no log line ever
carried a `trace_id` or `span_id`** — the whole point of writing JSON beside the
traces. It now asks the library for the hex identifiers it already knows how to
render, and three tests write a line inside a span and outside one; the one
inside carries exactly the identifiers its `traceparent` named. A dead `uuid ||
""` in the agent audit log, which the same run flagged, is gone too.
A tenth reads the span context the same wrong way, in
`VsmTracer.inject_context/1`, which puts a `traceparent` on the work handed to an
agent so the agent's spans hang under the pipeline that asked for them. It
happened to work: the fields are shifted by one, and the shift left a
32-character hex string in the slot the pattern called `trace_id` and an integer
in the slot it called `span_id`, so the header it built was right for the wrong
reason. It now asks the W3C propagator to spell the header, which is the only
place that knows how; four tests hold it to what a caller can see — the
traceparent names the span the call is inside, the caller's own keys survive, and
outside a span the map is untouched. `set_status/1` is the same story from the
other side: it passed a status record to a one-argument call where the library
documents `set_status(code, message)`, which made every one of its eighteen call
sites a dialyzer error. The spec of `low_space_agents/1` said `non_neg_integer()`
about an argument whose default is `nil`, and a `fetch_parent_ctx/1` with no
callers passed a pid where the library wants a depth, so it could only ever
raise; it is gone.

An eleventh was found by asking what `ElasticSchedulerHelpers` does, a module
nothing had ever called in a test. Whether a job needs an elastic agent is
answered by comparing it against the idle static agents, and that comparison was
written a second time here rather than taken from the scheduler. The two copies
disagreed: this one compared environment names case-sensitively, ignored the
agent a job is pinned to, and counted a job with no environments as handled by an
agent that belongs to one. The last is the expensive one, because the scheduler
will not assign a job with no environments to an agent that is in one: the job
would be classed as "a static agent can do this" while no agent could, and wait
forever without an elastic agent ever being provisioned. The rule now lives once,
as `Scheduler.job_matches_agent?/2`, and the scheduler assigns by it and the
elastic helpers ask with it. Twelve tests, three of which fail against the
duplicated copies.

A twelfth came out of writing the first tests for `ExGoCD.Cipher`, and is the
reason those tests exist. `unpad/1` read the last byte of a decrypted value as a
count and cut the buffer there, whatever the padding bytes said. A secure
environment variable stored under a key that has since been rotated therefore
decrypted to *something* — eleven zero bytes in the case the test caught — and a
pipeline would start with a corrupt value where it should have been told the
value could not be read. PKCS#7 is now checked, which is what GoCD's Java cipher
does; the malformed block the test builds on purpose comes back as `:error`. The
same work showed a second thing worth writing down: CBC without a MAC leaves a
small chance that any wrong key yields plausible bytes, so "the value does not
come back" is the promise a test may hold this scheme to, and that is what the
test now says.

`ExGoCD.Materials.GitClient` was removed rather than repaired. It declared a
behaviour, a `SystemImpl` that shells out to git and a mock, and all four config
files set `git_client:` — but no code calls it; Git materials go through
`ExGoCD.Materials.ScmClient`, whose mock honours the same `:mock_git_revision`
knob. A config key nothing reads is worse than no key at all, because changing it
looks like it should do something.

A thirteenth is about where a page has to be declared. `/admin/:tab` is a
catch-all that AdminLive answers, and two one-segment pages were declared after
it: the plugin dashboard, and an audit log page that was also a shadowed copy of
AdminLive's own tab. So `/admin/plugins` rendered AdminLive, which shows a card
whose only link is "Open Plugin Dashboard" pointing at `/admin/plugins` — a card
that led to itself, and a dashboard no URL reached. The plugin page is declared
before the catch-all now, and the audit log copy is gone, so the surviving
implementation is the one the URL and the sub-tab already reached. Two tests hold
the URLs to the pages they name.

The plugin dashboard also announced itself as `active` in green whatever the
registry said: the status was a literal, so a deployment with no plugin at all
saw a pulsing green dot reading "No agent_selector plugin registered · active".
It reads the registry now. And the audit log's filter form had `phx-change`
without an `id`, which LiveView warns about because it cannot keep a changed
input in the right form when there are several; it has an id.

A fourteenth is the most serious of the run, and it is not a fault of code but
of which pipeline a route sits behind. `/api/users` — list, read, create, update,
delete — was declared under `:api`, which authenticates a token and asks nothing
else. Anyone holding any token could therefore POST a user with
`roles: ["admin"]`, or delete the administrator who was about to remove them.
GoCD requires admin for this API. The five routes are under `:admin_api` now, at
both `/api/users` and `/go/api/users`, with thirteen tests; the five that matter
say a member is refused, and they fail against the old routing — a member could
create an admin, read the list, rename, and delete.

The same audit found other writes behind `:api` that GoCD reserves for admin, and
they are fixed in the same way once their callers were traced: nothing in this
repository, its assets, its Cypress specs or the Go agent calls
`DELETE /go/api/agents`, `PATCH /go/api/agents/:uuid`, enable, disable or
kill-running-tasks — the agent speaks `/agent` remoting, not this API. Those
seven routes are admin-only in both trees now, while registering and reading stay
open, and `POST /go/api/admin/encrypt` likewise. Eleven tests in
`authorisation_test.exs`, six of which fail against the old routing: a member
could disable, enable, rename, kill, delete and bulk-delete agents. `/api/test/*`
is left as it is on purpose — it is what Cypress drives the simulator through,
and the controller answers 403 unless the pool is the SQL sandbox, test mode is
on, or the environment is `dev`.

A fifteenth came out of writing the first tests for the stage API, and is the
smallest kind of fault: a path is what the caller typed, and `StageController`
believed it. `String.to_integer(counter_str)` on `/api/stages/p/not-a-number/…`
raised, so a typo in a URL became a 500 with a stack trace instead of a bad
request. Counters now go through `ControllerHelpers.parse_counter/1`, which
answers `{:ok, n}` or `{:error, :not_a_counter}`, and the four actions answer
400 with the name of the thing that must be a number. Ten tests, three of which
fail against the old code.

The same `String.to_integer` appeared at thirteen more places in controllers; two of those controllers are dealt with below and eleven remain — `pipeline_operations_controller` (twice), `personal_access_token_controller` (twice), `feeds_controller` (three times), `scm_controller`, and the pipeline-group (three times) and notification-filter admin controllers. Each will raise the same way, and `grep -rn "String.to_integer(" lib/ex_gocd_web/controllers` prints the list.

A sixteenth is the largest of the run, and the reason the pipeline-instance API
had never worked: `/api/pipelines/:name/history` and `/api/pipelines/:name/:counter`
answered 500 to every request. The JSON it builds read five fields the
`PipelineInstance` schema does not have — `scheduled_at`, `comment`,
`trigger_message`, `trigger_forced` and `approver` — and a struct answers a
missing key with a `KeyError`. What exists is `inserted_at` and a `build_cause`
map that the trigger path fills in, so the payload is now built from those; the
`comment` key is gone rather than always nil, because nothing stores a comment on
an instance. A seventeenth was one line further on: `show/2` preloaded
`stage_instances: [:stage, …]`, and `StageInstance` has no `:stage` association,
so that action raised `ArgumentError` before it could render anything. Five tests
for the controller, its first: the run as stored, the stages beneath it, a run
that does not exist, a pipeline that does not exist, and a counter that is not a
number.

Worth writing down beside these: dialyzer did not see either one. A struct that
comes back from `Repo` reaches it as an opaque type, so a field read that cannot
work is a runtime `KeyError` — exactly what a test that calls the endpoint finds
and a type check cannot.

Rather than look for more of those one at a time,
`test/ex_gocd_web/controllers/api/no_endpoint_crashes_test.exs` now asks every
parameterless GET endpoint in both API trees for an answer and fails if any of
them returns a 5xx: thirty-six requests, fifteen open and twenty-one as an admin.
It found the first of the eighteenth finding within a minute: the notification
filter API read `user_id` out of the request as if it were always there, so a
request without it raised `FunctionClauseError` — a 500 for a missing query
parameter. It refuses with a 400 now, as it does for a `user_id` that is not a
number.

Two more of the same in that controller: a body without `notification_filter` in
it raised the same way and now answers 400, and deleting an id nothing holds went
through `Repo.get!` and raised; the context answers `{:error, :not_found}` for an
id that is absent *or* not a uuid at all, which is what a mistyped one is. Six
tests. The sweep also raised coverage from 57.9 % to 58.8 % on its own, because
thirty-six controllers now answer at least once.

That sweep was then pointed at routes that take a name or an id, asking each for
something that is not there. Seven more faults fell out of one run. The materials
feed, `/api/feeds/materials/:pipeline/:counter/:fingerprint`, raised before it
could read a row: the query joined `Material` on `fingerprint` and on
`pipeline_instance_id`, and `Material` has neither — its fingerprint is derived
from type, url and branch by `Pipelines.material_fingerprint/1`, and it reaches a
run through `pipeline_material_revisions`, many-to-many into pipelines. That is a
nineteenth finding of the same shape as the pipeline instance API: an endpoint
that had never produced a feed. Entries also read `mod.username` and
`mod.inserted_at`, where a `Modification` carries `committer_name` and
`modified_time`. The feed now queries revisions, filters by the derived
fingerprint (it has no column to match on) and builds entries from the fields that
exist; three tests state what it should say.

The other six were admin `show` actions — artifact stores, auth configs, cluster
profiles, elastic agent profiles, package repositories, secret configs — each
fetching through `get_...!/1`, so an unknown id was a 500 with a stack trace. All
six now answer 404 through `ControllerHelpers.not_found/3`, in `show`, `update`
and `delete` alike, and their six private copies of a changeset-error formatter
became `format_errors/1` from the same helper module. Three tests for the artifact
stores cover the three actions; the sweep holds the other five controllers to the
same answer.

A twentieth came from giving pages the same treatment:
`test/ex_gocd_web/live/no_page_crashes_test.exs` mounts every page and every admin
tab — thirty-seven of them, eight open and twenty-nine as an admin — and names all
the ones that raise. One did: `/analytics/agents`. That tab is a function
component, and the template rendered it with `stats` only while the component also
reads `@latest_snapshot`; inside a component an assign it was not given does not
exist, so the tab raised `KeyError` for every visitor, always. The template passes
the assign now, and two tests state what the tab shows — the newest snapshot's
counts when there is one, and an honest empty page when there is not.

Pages need this sweep more than endpoints do: a page renders what several
contexts return at once, so one nil or one missing field takes the whole page
down rather than one response.

The same sweep, pointed at pages that name something absent, found a
twenty-first: `/admin/config_repos/:id/edit` raised `Ecto.Query.CastError` for an
id that is not a number, because a config repository's key is an integer and
`Repo.get/2` raises rather than answering nil for a value the key type cannot
hold. It answers the way the page's own "not found" branch already did — a
redirect to the list with a message — after checking the id can be one at all.
Two other pages in that run looked like offenders and were not: the sweep counted
every redirect as a failure, when a redirect carrying an error is precisely how a
page says the thing it was asked for is not there. It now accepts that, and holds
pages to raising nothing and redirecting with something to say.

A third sweep covers what is neither an API nor a page:
`test/ex_gocd_web/no_route_crashes_test.exs` asks the `/api_json` spelling of the
value-stream map, `/files` in all three of its spellings, `/auth/login` and
`/api/stats`. CCTray, the VSM JSON, artifacts and health already have tests of
their own, so the list is deliberately the routes beside them that nobody calls —
the ones an outside tool would reach before a test did. It found nothing to fix.

The three sweeps then turned out to be three copies of one helper, which the
gate's duplicate-code check said in as many words. `test/support/sweep.ex` holds
it now: a sweep supplies the paths, the way to ask, and what counts as an answer
for it — a response under 500 for a route, a mount or a redirect with a message
for a page.

A twenty-second came from the one piece of the config repo feature nobody had
tested: the engine that turns a cached workflow file into a pipeline. The parsers
and translators have tests of their own, which is why this survived — those tests
never passed a selection list, and the translators read one with
`get_in(selections, [:selected_jobs, "included"])`. A `ConfigRepoFileSelection`
stores that as a plain list, and `get_in` on a list asks `Access` for a key, which
answers `ArgumentError` for a list of strings. So the first non-empty selection
raised, and a config repository — the whole pipelines-as-code path — could not
produce a pipeline. It is read by `TranslatorHelpers.chosen/2` now, in five call
sites across both translators, which accepts either shape and reads an empty
choice as no choice: a file nobody chose anything from is translated whole rather
than into nothing.

Four tests for the engine, its first: a workflow file becomes a pipeline with its
stage, job and task; translating it twice leaves one pipeline rather than two; a
file set to be skipped makes none; and a file whose content was never cached is
reported rather than guessed at.

The OpenAPI document has four tests now, and needed no repair. `/api/openapi`
answers a valid OpenAPI 3 document whose every path the router actually serves —
asked by turning each path template into a concrete one and putting it to
`Phoenix.Router.route_info/4` — whose tags are all declared, and `/swaggerui`
serves the page that reads it. It matters more than a documentation check usually
would: `PutApiSpec` runs on every API request, so a document that cannot be built
takes the API with it.

The seed script a deploy runs had never been run by a test, and its own report
was wrong. `priv/repo/seeds.exs` opens by saying that fake pipeline history is
only seeded when `USE_MOCK_DATA=true`; the four report lines at the end of each
pipeline it creates said "4 historical runs" and "3 historical runs" whatever
the setting, so a production deploy logged history it had not written. The
reports are built from `history_note/1` now, which mentions runs only in mock
mode. Four tests hold the script: it seeds an empty database, it makes no
instances and claims none without mock data, it makes them and says so with
`USE_MOCK_DATA=true`, and running it a second time changes no count of
pipelines, stages, jobs, materials or users — the "safe to run twice" its own
docstring promises. The script is evaluated in the test's sandbox rather than
through `Release.seed/0`, which opens its own connection and would commit.

Running the seeds also gave the endpoint sweep a database with something in it,
and that is where the SCM endpoints turned out to be broken.
`api/scm_controller.ex` built each SCM's pipeline list from a field named
`pipeline_group`, which a pipeline does not have — the field is `group`. Every
pipeline has an SCM, so the listing raised `KeyError` and answered 500 on any
instance that had ever had one; the sweep had never seen it because an empty
database returns an empty list without building an SCM at all. Both sweeps now
run twice, once empty and once seeded, and the seeded one was checked by putting
the `KeyError` back: it names the endpoint and the field.

`GET /api/admin/scms/:id` was wrong in a quieter way: it used the id as a
position, `Enum.at(materials, id)`. So the SCM with id 1 was answered for id 2,
the highest id was answered with 404, and a path that was not a number raised in
`String.to_integer/1`. It finds by id now, and answers 404 for an id no material
holds. Five tests hold the pair: an SCM is answered by its own id wherever it
sits, it names the pipelines that use it, a listed SCM is listed once with every
pipeline that uses it, and both a non-numeric id and an unknown one are missing
rather than a crash.

`PUT /api/admin/pipeline_groups/:name` was routed and had no action to dispatch
to, so every rename raised `UndefinedFunctionError`; `resources` declares the
route and nothing checked that the controller answers it. It renames the group
and moves its pipelines in one statement now, reads the new name from
`{"group": {"name": ...}}` because a body key `name` is overwritten by the
path, answers 404 for a group nobody made and 422 for a body that names nothing.
Three tests.

Two controllers were routed nowhere at all and are deleted: `ExGoCDWeb.SCMController`
and `ExGoCDWeb.PipelineGroupController`, both shadowed by `ExGoCDWeb.API.*`
modules with the same names. The routes always resolved to the API ones, which is
why a sweep could not see the difference; the deleted pipeline-group controller
also moved its pipelines to a group called `"default"` where the rest of the
application uses `"defaultGroup"`.

Two LiveView forms had no id — the pipeline wizard and the admin pipeline
search — and form recovery is what an id buys: without one, a reconnect loses
what was typed. LiveView warns about it, in test runs only, thirty-one times per
run. Both have ids now, and `forms_test.exs` reads every `.ex` and `.heex` under
`lib/ex_gocd_web` and fails on a `phx-change` form without one, so the warning
cannot come back unnoticed.

The config repo admin API — the pipelines-as-code entry point — answered 500 on
every action that returned a repository. `json(conn, %{config_repo: repo})`
hands a struct to `Jason`, and `ConfigRepo` does not implement `Jason.Encoder`,
so the encoding raised `Protocol.UndefinedError`. The listing was in the same
state as soon as one repository existed. It goes through `ConfigRepoJSON.data/1`
now, which is how the other admin resources here already answer, and spells out
what an operator reads after a refresh rather than dumping every field. The same
four actions read their id with `Repo.get/2`, so a path that was not a number
raised `Ecto.Query.CastError`; `ConfigRepos.get_config_repo/1` answers `nil` for
an id that is not a number, which is what its seven callers already handle.

That API was reachable only at `/api/admin/config_repos`. Every other admin
endpoint here is served under `/go/api/admin/...` as well, and `api.go.cd`
documents this one under the `go` prefix, so a client written against GoCD's
documentation got a 404. The `go`-prefixed scope exists now, without the
`/cleanup` route: a destructive test hook does not need a second door.

Seven tests hold it: a listing with a repository in it, an answer by id, three
answers for an id that is not a number, a create with no url naming the field,
and an edit that changes what the body names and keeps the rest. The listing is
in the endpoint sweep too, so the seeded pass asks it with data present; the
`translate_errors/1` copy in that controller is the shared `format_errors/1` now.

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

`README.md` badges are hand-written and say 1243 tests and 27 Cypress specs.
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
