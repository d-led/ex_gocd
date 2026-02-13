# GoCD Agent (Go Implementation)

**100% compatible with original GoCD server protocol.**

A clean, modern Go implementation using libraries instead of CLI tools (go-git, not git binary).

## Protocol Compatibility

This agent supports **both** communication modes; **remoting API is the default** for compatibility with real GoCD:
- **Registration**: `POST /admin/agent` (form-based, with token from `GET /admin/agent/token?uuid=...`)
- **Default — Remoting API (real GoCD compatible):**
  - `POST /remoting/api/agent/get_cookie` then `POST /remoting/api/agent/get_work` on an interval
  - Auth: `X-Agent-GUID` + `Authorization` (token from registration)
  - Report: `report_current_status`, `report_completing`, `report_completed`
- **Optional — WebSocket** (new feature, e.g. for ex_gocd): set `AGENT_USE_WEBSOCKET=true` to use `/agent-websocket` and the same message types
- Console logs: HTTP POST with timestamped streaming
- Artifacts: multipart/form-data upload with MD5 checksum

Reference: [gocd-contrib/gocd-golang-agent](https://github.com/gocd-contrib/gocd-golang-agent)

## Architecture

```shell
agent/
├── cmd/
│   └── root.go         # CLI with cobra
├── main.go             # Entry point
├── internal/
│   ├── config/         # 12-factor config (env vars)
│   ├── agent/          # Main agent loop (register, ping, work)
│   ├── client/         # HTTP client (registration, artifacts, console)
│   ├── executor/       # Task execution (exec, go-git, artifacts)
│   └── console/        # Console log buffering & streaming
└── pkg/
    └── protocol/       # Protocol message definitions
```

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

The agent can **auto-register** with the ex_gocd Phoenix server. Use it when ready.

### With ex_gocd (this server)
```bash
# Server running at http://localhost:4000 — use remoting (default) or WebSocket when supported
./bin/gocd-agent --server-url http://localhost:4000 --work-dir ./work

# Or with go run (remoting API by default)
AGENT_SERVER_URL="http://localhost:4000" go run .

# Use WebSocket when the server supports it (new feature)
AGENT_SERVER_URL="http://localhost:4000" AGENT_USE_WEBSOCKET=true go run .
```

### Standalone (any GoCD-compatible server)
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
| `AGENT_USE_WEBSOCKET` | `false` | If `true`, use WebSocket for work (new feature). Default `false` = remoting API (compatible with real GoCD). |

**Communication mode:** By default the agent uses the **remoting API** (get_cookie, get_work polling), which is what real GoCD expects. Set `AGENT_USE_WEBSOCKET=true` to use WebSocket instead (e.g. for ex_gocd when it supports it).

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

### ✅ Basics ready (use with ex_gocd or original GoCD server)
- [x] Form-based registration at `POST /admin/agent` with token flow
- [x] WebSocket connection to `/agent-websocket`
- [x] Custom protocol messages (ping, setCookie, reregister, build, etc.)
- [x] Auto-registration with our Phoenix instance (HTTP; HTTPS with cert download supported for other servers)
- [x] Config (12-factor env vars), binary (no cgo)
- [x] **Task execution**: `exec` (run command + args) and `compose` (run subcommands in order)
- [x] Build session: create work dir, run command tree, report Building → Completing → Completed
- [x] Console log upload: buffered, timestamp prefix (HH:mm:ss.SSS), HTTP POST every 5s

### 🔄 In progress / next
- [ ] Artifact upload (multipart) and fetch-artifact
- [ ] Cancel build (kill running process when server sends cancelBuild)
- [x] Git material / checkout (`git` executor: clone with optional branch)
- [ ] Full TLS/certificate handling for HTTPS servers

### Testing with the original GoCD server
You can run this agent against the **original GoCD server** to run real pipelines:
1. Start original GoCD server (e.g. Docker: `docker run -d -p 8153:8153 -p 8154:8154 gocd/gocd-server`).
2. Run agent: `AGENT_SERVER_URL=http://localhost:8153/go ./bin/gocd-agent` (use the server’s URL and port).
3. In GoCD UI, add a pipeline with a job that uses an **exec task** (e.g. command `echo`, args `hello`).
4. The server will assign the job to the agent; the agent runs the task and reports back. Console output is POSTed to the server.
**Note:** The **real GoCD server uses remoting (polling), not WebSocket.** This agent registers over HTTP, then tries WebSocket; when that returns 404 it automatically switches to **remoting**: it calls `get_cookie` and then polls `get_work` and runs jobs. Use `AGENT_AUTO_REGISTER_KEY=<key>` if the server has auto-register enabled.

## Testing

```bash
# Run all tests
make test

# Run with coverage
make test-coverage
```

## Development

```bash
# Format code
make fmt

# Run linter
make lint

# Clean build artifacts
make clean
```
