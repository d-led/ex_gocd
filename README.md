# ExGoCD - Phoenix GoCD Rewrite

**A Phoenix Framework rewrite of GoCD with 100% protocol compatibility.**

## Critical Requirements

### Protocol Compatibility
This server MUST be **100% compatible** with original GoCD:
- **Agent Protocol**: WebSocket at `/agent-websocket` with custom message protocol
- **Agent Registration**: Form-based POST to `/admin/agent` (NOT `/api/agents`)
- **REST API**: Match [api.go.cd](../api.go.cd) spec exactly (versioned endpoints)

**Validation**: Both original GoCD agents AND our Go agent must work with this server.

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

Visit [`localhost:4000`](http://localhost:4000)

### With Agent
```bash
# Terminal 1: Phoenix server
mix phx.server

# Terminal 2: Go agent
cd agent && go run . --server-url http://localhost:4000
```

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

## Learn More

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
