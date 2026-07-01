# ExGoCD - Phoenix GoCD Rewrite

**A Phoenix Framework rewrite of GoCD with 100% protocol compatibility.**

## Critical Requirements

### Protocol Compatibility
This server MUST be **100% compatible** with original GoCD:
- **Agent Protocol**: WebSocket at `/agent-websocket` with custom message protocol
- **Agent Registration**: Form-based POST to `/admin/agent` (NOT `/api/agents`)
- **REST API**: Match [api.go.cd](../api.go.cd) spec exactly (versioned endpoints)

**Validation**: Both original GoCD agents AND our Go agent must work with this server.

**Compatibility**: The REST API, usage (URLs, headers), and agent protocols (registration + WebSocket) MUST stay compatible with GoCD. See [docs/rewrite.md](docs/rewrite.md) and [api.go.cd](../api.go.cd).

### Domain Fidelity
Use **exact** GoCD terminology and data model:
- Pipeline → Stage → Job → Task hierarchy
- Materials, Artifacts, Agents, Resources, Environments
- See [docs/rewrite.md](docs/rewrite.md) for complete domain model

## Getting Started

### Setup
```bash
# Install dependencies
mix setup

# Start Phoenix server
mix phx.server

# Or with IEx console
iex -S mix phx.server
```

The server reloads automatically on code/config changes unless there are unrecoverable config or compile errors.

Visit [`localhost:4000`](http://localhost:4000)

### With Go agent(s) — process-compose (recommended)

Start the full stack in one command: Phoenix server + CI agent + Docker agent.

```bash
# 1. Start infrastructure
docker compose up -d postgres jaeger otel-collector

# 2. Start all app processes
process-compose up
# (install: brew install f1bonacc1/tap/process-compose)
```

This starts `mix phx.server` on port 4000, plus two Go agents:
- **CI agent** — resources `elixir,postgres`, picks up build/test jobs
- **Docker agent** — resource `docker`, auto-detects Docker socket (Docker Desktop, Colima, etc.)

See `process-compose.yaml` for all configuration.

**Manual start** (if you prefer separate terminals):

```bash
# Terminal 1: Phoenix server
mix phx.server

# Terminal 2: CI agent (elixir,postgres resources)
./scripts/start-agent.sh

# Terminal 3: Docker agent (docker resource)
./scripts/start-docker-agent.sh
```

**Demo / development:**
- **Shared cookie**: In dev, the server returns a fixed token (`ex-gocd-demo-cookie`) so agent and server always match. The start script sets `EX_GOCD_DEMO_COOKIE` for the agent. For docker-compose, set the same `EX_GOCD_DEMO_COOKIE` on both server and agent services.
- **Auto-enable**: Newly registered agents are enabled by default in dev. Set `EX_GOCD_AUTO_ENABLE_AGENTS=0` to disable. In production, set `EX_GOCD_AUTO_ENABLE_AGENTS=true` to auto-enable.

Optional: set `AGENT_AUTO_REGISTER_KEY` (and optionally resources/environments) to match server config if you use auto-approval. See [agent/README.md](agent/README.md).

### Docker Compose Stack

```bash
docker compose up -d          # postgres + observability stack
docker compose up -d postgres # postgres only (for CI runner)
```

| Service | URL | Config |
|---|---|---|
| **ex_gocd app** | [localhost:4000](http://localhost:4000) | `config/dev.exs` |
| **Adminer** (DB browser) | [localhost:8092](http://localhost:8092/?pgsql=postgres&username=postgres&db=postgres&ns=public) | — |
| **Grafana** (dashboards) | [localhost:3000](http://localhost:3000) | `grafana/grafana.ini`, `grafana/provisioning/` |
| **Jaeger** (traces) | [localhost:16686](http://localhost:16686/search) | all-in-one, ephemeral |
| **OTel Collector** | `localhost:4318` (HTTP), `localhost:4317` (gRPC) | `otel/collector-config.yml` |
| **Grafana Renderer** | `localhost:3081` (internal) | — |
| **Postgres** | `localhost:5432` (`postgres:postgres`) | `docker-compose.yml` env vars |
| **smtp4dev** (email testing) | [localhost:8025](http://localhost:8025) | SMTP on `:2525`, no auth |

Pre-configured dashboard: `grafana/provisioning/dashboards/ci-observability/pipeline-observability.json`

### Observability

Built-in observability with **zero external tools required**:

- **[Grafana](http://localhost:3000)** — pre-configured CI pipeline dashboard with Jaeger trace explorer
- **[Jaeger](http://localhost:16686)** — distributed tracing of pipeline VSM (each trigger → correlated spans for stages/jobs)
- **OpenTelemetry** — OTLP export from server to collector → Jaeger. Config in `config/config.exs` (`:ex_gocd, :otel`), setup in `lib/ex_gocd/otel.ex` (WIP)

## Documentation

- [Architecture & Parity](docs/architecture_and_parity.md) — stack, cluster topology, plugin system, feature parity matrix
- [Comprehensive Parity Plan](docs/comprehensive_parity_plan.md) — detailed audited parity report
- [Development Status](docs/status.md)
- [Agent Implementation](agent/README.md)

## Technical Architecture

- **Server & Web UI**: [Phoenix LiveView](https://www.phoenixframework.org/) (not a Single-Page App, nor a pure server-side rendering. Live views with simplicity of the Actor Model)
- **Database**: [Ecto](https://github.com/elixir-ecto/ecto) with PostgreSQL for persistence
- **Agent**: Go (statically linked, no cgo)
- **Testing**: ExUnit + LiveView testing

### Testing

- **Full suite** (needs Postgres): `mix test` — runs `ecto.create`, `ecto.migrate`, then tests.
- **Without Postgres**: `EX_GOCD_TEST_NO_DB=1 mix test_no_db` — skips DB; use for e.g. converter tests. Example: `EX_GOCD_TEST_NO_DB=1 mix test_no_db test/mix/tasks/convert_gocd_css_test.exs`

## Learn More

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
