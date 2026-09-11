# GoCD Agent (Go Implementation)

A Go implementation of a GoCD build agent.

## Protocol Compatibility — current state

**The agent does not yet speak GoCD's agent protocol.** It uses a WebSocket
transport that was removed from GoCD in 19.6.0
(`d45efb4d25 "Remove build session and agent websocket"`), so it can only talk
to ExGoCD, never to a real GoCD server. The official Java agent's protocol is
HTTP remoting, and that is what this agent needs to implement.

The protocol to implement is fully specified in
[`../test/fixtures/remoting/`](../test/fixtures/remoting/README.md) — captured
verbatim from an official Java agent talking to an official GoCD server. The
ExGoCD server already speaks it (`ExGoCDWeb.AgentRemotingController`), so the
agent can be developed and tested against ExGoCD before being pointed at a real
GoCD server.

What the official agent does, and therefore what this agent must do:

| Step | Endpoint |
| --- | --- |
| Fetch a registration token | `GET /go/admin/agent/token?uuid=<uuid>` |
| Register | `POST /go/admin/agent` (form-encoded) |
| Fetch session cookie | `POST /go/remoting/api/agent/get_cookie` |
| Heartbeat / poll | `POST /go/remoting/api/agent/ping`, `.../get_work` |
| Report progress | `POST /go/remoting/api/agent/report_current_status`, `report_completing`, `report_completed` |
| Append console output | `PUT /go/remoting/files/<locator>/cruise-output/console.log?attempt=1&buildId=<id>` |

Every remoting call carries `Accept: application/vnd.go.cd+json`,
`Content-Type: application/json; charset=UTF-8`, `X-Agent-GUID: <uuid>` and
`Authorization: <token>`, with a JSON body whose `type` field names the request
(`PingRequest`, `GetWorkRequest`, …).

## Architecture

```shell
agent/
├── cmd/
│   └── root.go         # CLI with cobra
├── main.go             # Entry point
├── internal/
│   ├── config/         # 12-factor config (env vars)
│   ├── agent/          # Agent loop (register, ping, work)
│   ├── client/         # HTTP client (registration, artifacts, console)
│   ├── executor/       # Task execution (exec, go-git, artifacts)
│   ├── registration/   # Token + form registration
│   └── websocket/      # WebSocket transport — to be replaced by HTTP remoting
└── pkg/
    └── protocol/       # Message definitions
```

## What is reusable

- Config package (12-factor env vars)
- Executor (exec, go-git for SCM)
- Console log buffering
- Artifact handling
- Binary build (no cgo, statically linked)

## Building

```bash
# Install dependencies
make deps

# Build the agent
make build

# Run tests
make test
```

## Running

### Standalone
```bash
./bin/gocd-agent --server-url http://localhost:4000 --work-dir ./work
```

### With process-compose
```bash
# From the ex_gocd directory
process-compose up
```

## Configuration

The agent follows 12-factor app principles using Viper for configuration management.

### Environment Variables (AGENT_ prefix)

All configuration uses the `AGENT_` prefix. Configuration keys with dots are converted to underscores.

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `AGENT_SERVER_URL` | `http://localhost:8153/go` | GoCD server URL |
| `AGENT_WORK_DIR` | `./work` | Working directory for the agent |
| `AGENT_HEARTBEAT_INTERVAL` | `10s` | Heartbeat interval (duration format) |
| `AGENT_WORK_POLL_INTERVAL` | `5s` | Work polling interval (duration format) |
| `AGENT_AUTO_REGISTER_KEY` | - | Auto-registration key |
| `AGENT_AUTO_REGISTER_RESOURCES` | - | Comma-separated resources |
| `AGENT_AUTO_REGISTER_ENVIRONMENTS` | - | Comma-separated environments |
| `AGENT_AUTO_REGISTER_ELASTIC_AGENT_ID` | - | Elastic agent ID |
| `AGENT_AUTO_REGISTER_ELASTIC_PLUGIN_ID` | - | Elastic plugin ID |
| `EX_GOCD_DEMO_COOKIE` or `AGENT_DEMO_COOKIE` | - | Shared demo cookie: use this token for registration so server and agent always match (set same value on server in docker-compose or use dev server default) |

**Examples:**

```bash
# Basic usage
AGENT_SERVER_URL="http://localhost:4000" go run .

# With auto-registration
AGENT_SERVER_URL="https://gocd.example.com" \
AGENT_AUTO_REGISTER_KEY="secret-key" \
AGENT_AUTO_REGISTER_RESOURCES="docker,linux" \
AGENT_AUTO_REGISTER_ENVIRONMENTS="production" \
go run .

# Custom intervals
AGENT_SERVER_URL="http://localhost:4000" \
AGENT_HEARTBEAT_INTERVAL="30s" \
AGENT_WORK_POLL_INTERVAL="10s" \
go run .
```

### Legacy Environment Variables (Deprecated)

The old `GOCD_` prefix is deprecated but may still work depending on your viper setup:
- ❌ `GOCD_SERVER_URL` → ✅ `AGENT_SERVER_URL`
- ❌ `GOCD_AGENT_WORK_DIR` → ✅ `AGENT_WORK_DIR`
- ❌ `GOCD_AUTO_REGISTER_KEY` → ✅ `AGENT_AUTO_REGISTER_KEY`

## Agent Identity

On first run, the agent creates a `.agent-id.json` file in the work directory containing:
- UUID (persisted across restarts)
- Hostname
- IP address

## Implementation Status

### ✅ Already working
- Registration: token fetch, form POST, cookie retrieval
- Task execution (exec, go-git for SCM)
- Console log buffering and upload
- Artifact upload/download
- Agent identity, restart policy, orphan-container reaping
- OpenTelemetry export

### ❌ Still missing for drop-in compatibility
- HTTP remoting client for `POST /go/remoting/api/agent/*`
- GoCD `BuildWork` decoding (the shapes are in `../test/fixtures/remoting/`)
- `report_current_status` / `report_completing` / `report_completed` reports
- Console-log appends to `/remoting/files/.../console.log`
- `get_work` polling loop replacing the WebSocket loop

The existing WebSocket transport is not a path to compatibility and should be
deleted once the remoting client lands.

## Testing

```bash
make test

# Run with coverage
make test-coverage
```

`test-original-gocd.sh` is currently **not** a compatibility test: it points the
agent at a real GoCD server and cannot succeed until the HTTP remoting client is
implemented. Treat it as a failing acceptance test, not as evidence of
compatibility.

## Development

```bash
# Format code
make fmt

# Run linter
make lint

# Clean build artifacts
make clean
```
