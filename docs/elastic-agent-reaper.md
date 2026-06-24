# Elastic Agent Reaper Design

## Problem

When a Docker-elastic GoCD agent crashes or is killed mid-build, Docker containers spawned during the build become **orphans** — still running (or stopped), consuming resources, with no parent to clean them up.

The solution is the **Testcontainers Ryuk pattern**: label containers at creation time with the parent agent's identity, then reap any survivors on next startup.

## Architecture

```
Agent starts
  ├─ Reaper: docker ps -a --filter label=com.gocd.agent-uuid={uuid} -q
  │   └─ docker rm -f <any orphans from prior crash>
  ├─ Registers with GoCD server
  └─ Build assigned
      └─ Pipeline runs `docker run myimage`
          └─ Interceptor rewrites to:
              docker run --label com.gocd.agent-uuid={uuid} myimage
```

## Label Convention

| Label | Value | Purpose |
|---|---|---|
| `com.gocd.agent-uuid` | Agent's stable UUID (persisted in `agent.uuid`) | Identifies which agent spawned the container |
| `com.gocd.build-id` | GoCD build locator (e.g., `demo/5/build/1`) | Per-build traceability and debugging |

Labels use reverse-DNS convention (`com.gocd.*`) following Docker best practices.

## Components

### `agent/internal/docker/labels.go`
Label constants. Single source of truth for label keys.

### `agent/internal/docker/reaper.go`
`Reaper` struct with `ReapOrphans(ctx)` method.

- Runs **once at agent startup** (in `main.go`, after UUID resolution, before PID file and main loop)
- Executes `docker ps -a --filter label=com.gocd.agent-uuid={uuid} -q` then `docker rm -f` on each result
- **Non-fatal**: if Docker is unavailable, logs a warning and continues
- Currently uses Docker CLI (`exec.Command`); can be swapped to Go SDK later

### `agent/internal/docker/intercept.go`
`InterceptDockerArgs(cmdPath, args, agentUUID, buildID)` injects labels.

- Called in `runOneCommand()` before `exec.Command()`
- Only intercepts `docker run` and `docker create` (not `docker build`, `docker ps`, etc.)
- Inserts `--label` flags before the image name, correctly handling:
  - Boolean flags (`--rm`, `-d`)
  - Key-value flags (`-e FOO=bar`, `-v /host:/container`, `--name c`)
  - Mixed flag types

## Future: Go SDK Provisioning

When the elastic agent gains server-side provisioning (Phase 5 of [external-ci-pipeline-sync-plan.md](./external-ci-pipeline-sync-plan.md)), the same labels will be used by the `DockerProvisioner` to create containers via the Docker Go SDK (`github.com/docker/docker/client`). The reaper and intercept patterns remain unchanged — the SDK just replaces CLI calls with typed API calls.

## Files

| File | Status |
|---|---|
| `agent/internal/docker/labels.go` | ✅ Created |
| `agent/internal/docker/reaper.go` | ✅ Created |
| `agent/internal/docker/intercept.go` | ✅ Created |
| `agent/internal/docker/intercept_test.go` | ✅ Created (12 tests) |
| `agent/main.go` | ✅ Modified — reaper hook |
| `agent/internal/agent/agent.go` | ✅ Modified — intercept hook |
