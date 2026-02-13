# GoCD Agent (Go Implementation)

**100% compatible with original GoCD server protocol.**

A clean, modern Go implementation using libraries instead of CLI tools (go-git, not git binary).

## Protocol Compatibility

This agent implements the **exact same WebSocket + custom protocol** as original GoCD:
- Registration: `POST /admin/agent` (form-based, with token)
- Communication: WebSocket at `/agent-websocket`
- Messages: `ping`, `build`, `reportCurrentStatus`, `reportCompleted`, etc.
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
# Server running at http://localhost:4000
./bin/gocd-agent --server-url http://localhost:4000 --work-dir ./work

# Or with go run
AGENT_SERVER_URL="http://localhost:4000" go run .
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

### ✅ Basics ready (use with ex_gocd server)
- [x] Form-based registration at `POST /admin/agent` with token flow
- [x] WebSocket connection to `/agent-websocket`
- [x] Custom protocol messages (ping, setCookie, reregister, build, etc.)
- [x] Auto-registration with our Phoenix instance (HTTP; HTTPS with cert download supported for other servers)
- [x] Config (12-factor env vars), executor (exec, go-git), console buffering, binary (no cgo)

### 🔄 In progress / next
- [ ] Job execution end-to-end (build → run tasks → report completed)
- [ ] Console log upload (HTTP POST) and artifact upload (multipart)
- [ ] Connection retry and reconnection polish
- [ ] Full TLS/certificate handling for HTTPS servers

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
