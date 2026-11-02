# ExGoCD

A GoCD server and GoCD agent, rewritten: the server in Elixir/Phoenix LiveView, the
agent in Go. Same pipeline model, same remoting protocol the GoCD agent speaks.

## Run it

Server, database, one connected agent and demo pipelines, in open mode — nobody logs
in:

```bash
curl -fsSLO https://raw.githubusercontent.com/d-led/ex_gocd/main/docker-compose.quickstart.yml
docker compose -f docker-compose.quickstart.yml up --build
```

Then open <http://localhost:4000>. The demo pipelines are in the group `default`.
The first build takes a few minutes; later starts are seconds.

The stack is Postgres 18, the server, and the Go agent, which registers itself and
picks up work. `EX_GOCD_SKIP_USER_SEED=1` is what keeps open mode: the seed script's
demo users include an admin, and an admin in the database turns open mode off.

Start from zero again with `docker compose -f docker-compose.quickstart.yml down -v`.

## Run it natively

Needs Elixir 1.20, Erlang 29, Go 1.26 and a Postgres you can reach.

```bash
mix setup                     # deps, database, seeds, assets
mix phx.server                # http://localhost:4000
```

An agent is optional; without one, pipelines queue and nothing runs:

```bash
cd agent && GOCD_SERVER_URL=http://localhost:4000 go run .
```

## What works

| Area | State |
| --- | --- |
| Pipelines, stages, jobs, materials, fan-in, locking, manual and auto triggers | working, tested |
| Go agent: registration, work assignment, console upload, artifacts, cancellation | working, tested |
| UI: dashboard, pipeline activity, stage details, VSM, Gantt, admin pages | working, main paths tested |
| Config XML import/export, config repos (JSON, YAML, GitHub Actions, GitLab CI) | working, tested |
| Elastic agents: Kubernetes and Docker | working; the pod and container calls have no tests |
| OpenTelemetry traces and metrics, Jaeger, Grafana | wired; dashboards in `grafana/` |
| Plugins: agent selectors, auth providers, notification sinks, org hierarchy | wired through a plugin registry |
| RBAC: roles, per-environment policies, personal access tokens, encryption | working, tested |

What is measured and what is not is in [docs/STATUS.md](docs/STATUS.md), including the
modules no test reaches. Feature-by-feature detail, with the GoCD class each module
corresponds to, is in [docs/PARITY.md](docs/PARITY.md).

## Compatibility with GoCD

- **The Go agent works against this server**, and this agent works against a real GoCD
  server: both speak GoCD's remoting API (`/remoting/api/agent/*`).
- **The HTTP API is a subset**, not all of api.go.cd: 157 of the 181 documented
  endpoints have a route, and the rest are features this rewrite does not have. The
  documented paths are served under both `/api/...` and the `/go/api/...` spelling
  GoCD uses.
- **The UI is a rewrite**, not a copy: same pages and flows, different HTML.
- **Config XML** is GoCD's format, so an existing `cruise-config.xml` imports.

## Tests

```bash
mix test.setup                  # once: create and migrate the test database
mix test                        # the whole suite
EX_GOCD_TEST_NO_DB=1 mix test   # only what needs no database
bash scripts/quality-gate.sh    # format, compile, Sobelow, Credo, tests, Go, JS, links
```

`mix test` needs Postgres. Point it elsewhere with `PGHOST`/`PGPORT`, or set
`DATABASE_URL`.

## Development stack

`docker-compose.yml` is the one for working on the project: Postgres, Adminer, Jaeger,
Grafana, Loki, Fluent Bit, smtp4dev and a k3s cluster for elastic agents.
`process-compose.yaml` starts the server and two agents on the host against it.

```bash
docker compose up -d postgres jaeger otel-collector
process-compose up
```

## Where to read next

- [docs/STATUS.md](docs/STATUS.md) — measured state: tests, coverage, faults found.
- [docs/PARITY.md](docs/PARITY.md) — GoCD feature map and the module for each.
- [docs/plugin_authoring.md](docs/plugin_authoring.md) — writing a plugin.
- [agent/README.md](agent/README.md) — agent configuration and behaviour.

## License

Mozilla Public License 2.0 — see [LICENSE](LICENSE).
