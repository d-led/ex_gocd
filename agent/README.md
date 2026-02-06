# GoCD Agent (Go Implementation)

A clean, well-tested Go implementation of a GoCD agent that communicates with the Phoenix-based GoCD server.

## Architecture

```shell
agent/
├── cmd/
│   └── agent/          # Main entry point
├── internal/
│   ├── config/         # Configuration
│   ├── controller/     # Agent lifecycle management
│   ├── identifier/     # Agent UUID and identity
│   ├── registration/   # Server registration
│   ├── polling/        # Work polling (TODO)
│   ├── executor/       # Job execution (TODO)
│   └── reporter/       # Status reporting (TODO)
└── pkg/
    └── api/           # Server API client (TODO)
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

The agent can be configured via:

1. **Command-line flags**:
   - `--server-url`: GoCD server URL (default: http://localhost:4000)
   - `--work-dir`: Agent working directory (default: ./work)

2. **Environment variables**:
   - `GOCD_AUTO_REGISTER_KEY`: Auto-registration key

## Agent Identity

On first run, the agent creates a `.agent-id.json` file in the work directory containing:
- UUID (persisted across restarts)
- Hostname
- IP address

## Features

### ✅ Phase 1: Registration & Heartbeat
- [x] Agent identifier generation and persistence
- [x] Registration with server
- [x] Periodic heartbeat
- [x] Graceful shutdown

### 🚧 Phase 2: Work Polling (TODO)
- [ ] Poll server for assigned jobs
- [ ] Handle "no work" gracefully
- [ ] Connection retry logic

### 🚧 Phase 3: Job Execution (TODO)
- [ ] Execute tasks (exec, ant, rake, etc.)
- [ ] Environment variable handling
- [ ] Console log streaming

### 🚧 Phase 4: Status Reporting (TODO)
- [ ] Job state transitions
- [ ] Console log streaming
- [ ] Build completion

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
