# GoCD Agent (Go Implementation)

A Go implementation of a GoCD build agent.

## Protocol

The agent speaks GoCD's HTTP remoting protocol — the same one the official Java
agent uses. GoCD removed its WebSocket transport in 19.6.0
(`d45efb4d25 "Remove build session and agent websocket"`); the agent now does
everything over `POST /go/remoting/api/agent/*`:

| Step | Endpoint |
| --- | --- |
| Fetch a registration token | `GET /go/admin/agent/token?uuid=<uuid>` |
| Register | `POST /go/admin/agent` (form-encoded) |
| Fetch session cookie | `POST /go/remoting/api/agent/get_cookie` |
| Heartbeat / poll | `POST /go/remoting/api/agent/ping`, `.../get_work` |
| Report progress | `POST /go/remoting/api/agent/report_current_status`, `report_completing`, `report_completed` |
| Check if a build was cancelled | `POST /go/remoting/api/agent/is_ignored` |
| Append console output | `PUT /go/remoting/files/<locator>/cruise-output/console.log?attempt=1&buildId=<id>` |

Every remoting call carries `Accept: application/vnd.go.cd+json`,
`Content-Type: application/json; charset=UTF-8`, `X-Agent-GUID: <uuid>` and
`Authorization: <token>`, with a JSON body whose `type` field names the request
(`PingRequest`, `GetWorkRequest`, …).

The wire contract is captured verbatim in
[`../test/fixtures/remoting/`](../test/fixtures/remoting/README.md) and decoded
by `internal/remoting/wire_test.go`.

## Architecture

```shell
agent/
├── cmd/
│   └── root.go         # CLI with cobra
├── main.go             # Entry point (restart policy, identity, reaping)
├── internal/
│   ├── config/         # 12-factor config (env vars)
│   ├── agent/          # Poll loop + build executor (register, ping, get_work)
│   ├── remoting/       # GoCD HTTP remoting client + BuildWork decoding
│   ├── registration/   # Token + form registration + TLS certs
│   ├── docker/         # Container interception + orphan reaping
│   ├── log/            # zerolog setup + runtime metrics
│   └── telemetry/      # OpenTelemetry relay
└── pkg/
    └── protocol/       # Domain types shared by transport and executor
```

## Features

- Registration (token fetch, form POST, pending-approval retry, TLS certs)
- HTTP remoting polling loop (ping / get_work / is_ignored / reports)
- Build execution (exec, git materials, artifacts)
- Console log streaming to the server
- Artifact upload/download
- Agent identity, restart policy, orphan-container reaping
- OpenTelemetry export
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
AGENT_SERVER_URL=http://localhost:4000 AGENT_WORK_DIR=./work ./bin/gocd-agent
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

### ✅ Working
- Registration: token fetch, form POST, pending-approval retry, TLS certificates
- HTTP remoting client: `ping`, `get_work`, `get_cookie`, `is_ignored`, `report_*`
- `BuildWork` decoding into the executor's command tree
- Task execution (exec, git materials, artifacts)
- Console log appends to `/remoting/files/.../console.log`
- Artifact upload/download
- Agent identity, restart policy, orphan-container reaping
- OpenTelemetry export

### ❌ Not yet supported
- Artifact plans in official `BuildWork` assignments are parsed but not yet
  mapped to upload/fetch commands (ExGoCD sends them as `exec` nodes instead).

## Testing

```bash
make test

# Run with coverage
make test-coverage
```

`test-original-gocd.sh` is the compatibility acceptance test: it builds the
agent, points it at a real GoCD server, and verifies the agent registers with
the requested resources. Requires a running GoCD server (see the script
header).

## Development

```bash
# Format code
make fmt

# Run linter
make lint

# Clean build artifacts
make clean
```
