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

### 🚧 Phase 1: WebSocket Protocol (TODO - REQUIRED FOR COMPATIBILITY)
- [ ] WebSocket connection to `/agent-websocket`
- [ ] Form-based registration at `/admin/agent` with token flow
- [ ] Custom protocol message parsing (ping, build, setCookie, reregister, etc.)
- [ ] Proper TLS/certificate handling
- [ ] Connection retry and reconnection logic

### ⚠️ Current State: REST/JSON (INCOMPATIBLE - NEEDS REWRITE)
- [x] ~~REST registration~~ (uses `/api/agents` - wrong endpoint!)
- [x] ~~JSON polling~~ (should use WebSocket, not HTTP polling!)
- [x] Task execution (exec, go-git) - ✅ Keep this
- [x] Console log buffering - ✅ Keep this, adapt upload to HTTP POST
- [x] Artifact handling structure - ✅ Keep this, adapt to multipart

### 🎯 What to Keep
- Config package (12-factor env vars) ✅
- Executor (exec, go-git for Git operations) ✅
- Console log buffering (change upload to match protocol) ✅
- Task execution logic ✅
- Binary build (no cgo, statically linked) ✅

### 🔄 What to Rewrite
- Replace REST client with WebSocket connection
- Replace JSON protocol with custom message types
- Change registration from JSON to form POST
- Implement ping/heartbeat via WebSocket messages
- Get work via WebSocket `build` messages (not HTTP polling)

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
