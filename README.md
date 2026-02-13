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

### With Go agent (auto-registration)

The Go-based agent can register itself automatically with this server. Use it when you're ready to run work on agents.

```bash
# Terminal 1: Phoenix server (in dev uses shared demo cookie automatically)
mix phx.server

# Terminal 2: Go agent (script sets shared cookie so server and agent always match)
./scripts/start-agent.sh
```

Or run the agent from the agent directory: `cd agent && go run .` (set `AGENT_SERVER_URL` if needed).

**Demo / development:**
- **Shared cookie**: In dev, the server returns a fixed token (`ex-gocd-demo-cookie`) so agent and server always match. The start script sets `EX_GOCD_DEMO_COOKIE` for the agent. For docker-compose, set the same `EX_GOCD_DEMO_COOKIE` on both server and agent services.
- **Auto-enable**: Newly registered agents are enabled by default in dev. Set `EX_GOCD_AUTO_ENABLE_AGENTS=0` to disable. In production, set `EX_GOCD_AUTO_ENABLE_AGENTS=true` to auto-enable.

Optional: set `AGENT_AUTO_REGISTER_KEY` (and optionally resources/environments) to match server config if you use auto-approval. See [agent/README.md](agent/README.md).

## Documentation

- [Rewrite Plan & Requirements](docs/rewrite.md) - **READ THIS FIRST**
- [Development Status](docs/status.md)
- [Agent Implementation](agent/README.md)

## Architecture

- **Web**: Phoenix LiveView (no React/Mithril - pure server-side)
- **Styling**: Direct CSS conversion from original GoCD SCSS
- **Database**: PostgreSQL via Ecto
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
