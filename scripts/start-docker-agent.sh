#!/usr/bin/env bash
# ── ex_gocd Docker Agent ───────────────────────────────────────────────
# Starts a GoCD agent with Docker socket access for running containerized
# CI jobs. Auto-detects Docker socket from:
#   1. DOCKER_HOST env var (e.g. tcp://, unix://)
#   2. Active docker context (docker context ls)
#   3. Common paths: ~/.docker/run/docker.sock, ~/.colima/default/docker.sock,
#      /var/run/docker.sock
#
# Usage:
#   ./scripts/start-docker-agent.sh
#   AGENT_DOCKER_SOCKET=/custom/path ./scripts/start-docker-agent.sh
#   AGENT_NEW_UUID=1 ./scripts/start-docker-agent.sh  # fresh identity
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT/agent"

# ── Detect Docker socket ──────────────────────────────────────────────
detect_docker_socket() {
  # 1. Explicit override
  if [[ -n "${AGENT_DOCKER_SOCKET:-}" ]]; then
    echo "$AGENT_DOCKER_SOCKET"
    return
  fi

  # 2. DOCKER_HOST env var
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    echo "$DOCKER_HOST"
    return
  fi

  # 3. Active docker context socket
  if command -v docker &>/dev/null; then
    local ctx_socket
    ctx_socket=$(docker context ls --format '{{.DockerEndpoint}}' 2>/dev/null | grep 'unix://' | head -1 | sed 's|^unix://||')
    if [[ -n "$ctx_socket" ]] && [[ -S "$ctx_socket" ]]; then
      echo "unix://$ctx_socket"
      return
    fi
  fi

  # 4. Common paths
  for sock in \
    "$HOME/.docker/run/docker.sock" \
    "$HOME/.colima/default/docker.sock" \
    "/var/run/docker.sock"; do
    if [[ -S "$sock" ]]; then
      echo "unix://$sock"
      return
    fi
  done

  # 5. Docker Desktop raw socket (macOS)
  local dd_sock="$HOME/Library/Containers/com.docker.docker/Data/docker.raw.sock"
  if [[ -S "$dd_sock" ]]; then
    echo "unix://$dd_sock"
    return
  fi

  echo ""  # not found
}

DOCKER_SOCKET=$(detect_docker_socket)
if [[ -z "$DOCKER_SOCKET" ]]; then
  echo "WARNING: No Docker socket found. Agent will start without Docker access."
  echo "  Set AGENT_DOCKER_SOCKET=/path/to/socket to override."
fi

# ── Agent identity ────────────────────────────────────────────────────
: "${AGENT_UUID:=docker-agent-00000000-0000-4000-a000-000000000001}"
if [[ "${AGENT_NEW_UUID:-}" == "1" ]]; then
  unset AGENT_UUID
fi

# ── Work dir ──────────────────────────────────────────────────────────
AGENT_WORK_DIR="${AGENT_WORK_DIR:-$HOME/.ex_gocd/docker-agent}"
mkdir -p "$AGENT_WORK_DIR"

# ── Resources ─────────────────────────────────────────────────────────
: "${AGENT_AUTO_REGISTER_RESOURCES:=docker}"
if [[ -n "$DOCKER_SOCKET" ]]; then
  AGENT_AUTO_REGISTER_RESOURCES="docker,${AGENT_AUTO_REGISTER_RESOURCES}"
fi

export AGENT_SERVER_URL="${AGENT_SERVER_URL:-http://localhost:4000}"
export AGENT_WORK_DIR="$AGENT_WORK_DIR"
export AGENT_UUID="${AGENT_UUID:-}"
export AGENT_AUTO_REGISTER_RESOURCES="$AGENT_AUTO_REGISTER_RESOURCES"
export AGENT_HOSTNAME="${AGENT_HOSTNAME:-docker-agent}"
export EX_GOCD_DEMO_COOKIE="${EX_GOCD_DEMO_COOKIE:-ex-gocd-demo-cookie}"

# ── Kill stale agent ──────────────────────────────────────────────────
shopt -s nullglob
for pidfile in "$AGENT_WORK_DIR/agent"/*.pid; do
  [[ -f "$pidfile" ]] || continue
  OLD_PID=$(cat "$pidfile" 2>/dev/null || true)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "→ Killing stale docker-agent (PID $OLD_PID)"
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$pidfile"
done
shopt -u nullglob

# ── OpenTelemetry ─────────────────────────────────────────────────────
export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-otlp}"
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-localhost:4318}"
export OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-gocd-docker-agent}"

# ── Show ──────────────────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────────"
echo "Docker Agent → ${AGENT_SERVER_URL}"
echo "  UUID:      ${AGENT_UUID:-<will generate fresh>}"
echo "  Work dir:  $AGENT_WORK_DIR"
echo "  Socket:    ${DOCKER_SOCKET:-NOT FOUND}"
echo "  Resources: $AGENT_AUTO_REGISTER_RESOURCES"
echo "  Tracing:   $OTEL_EXPORTER_OTLP_ENDPOINT (service: $OTEL_SERVICE_NAME)"
echo "──────────────────────────────────────────────────────────────────"

# ── Start agent ────────────────────────────────────────────────────────
cd "$AGENT_DIR"
exec go run .
