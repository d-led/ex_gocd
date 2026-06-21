#!/usr/bin/env bash
# ── ex_gocd Go Agent ───────────────────────────────────────────────────
# Starts the Go agent with UUID-based identity. Auto-detects CI mode when
# called as run-ci-agent.sh or with AGENT_CI_MODE=1.
#
# Usage:
#   ./scripts/start-agent.sh                 # default dev agent
#   AGENT_NEW_UUID=1 ./scripts/start-agent.sh # fresh identity
#   AGENT_UUID=my-agent-1 ./scripts/start-agent.sh  # specific UUID
#
# Env vars: AGENT_SERVER_URL, AGENT_WORK_DIR, AGENT_AUTO_REGISTER_RESOURCES,
#           AGENT_AUTO_REGISTER_ENVIRONMENTS, AGENT_AUTO_REGISTER_KEY,
#           AGENT_HOSTNAME, AGENT_UUID, AGENT_NEW_UUID, EX_GOCD_DEMO_COOKIE
# Elastic mode (provision on demand, self-terminate when idle):
#   AGENT_AUTO_REGISTER_ELASTIC_AGENT_ID=... \
#   AGENT_AUTO_REGISTER_ELASTIC_PLUGIN_ID=cd.go.contrib.elastic-agent.docker \
#   AGENT_AUTO_REGISTER_RESOURCES= \
#   AGENT_IDLE_TIMEOUT=300s \
#   ./scripts/start-agent.sh
set -euo pipefail
shopt -s nullglob 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT/agent"

# ── Agent identity ────────────────────────────────────────────────────
# Default dev UUID — stable across restarts.
: "${AGENT_UUID:=dev-agent-00000000-0000-4000-a000-000000000001}"
if [[ "${AGENT_NEW_UUID:-}" == "1" ]]; then
  unset AGENT_UUID  # let Go generate a fresh UUID
fi

# ── Elastic agent mode ────────────────────────────────────────────────
# When elastic IDs are set, clear resources (server rejects elastic agents with resources).
# Also default AGENT_IDLE_TIMEOUT to 5 min if not set.
if [[ -n "${AGENT_AUTO_REGISTER_ELASTIC_AGENT_ID:-}" ]] && [[ -n "${AGENT_AUTO_REGISTER_ELASTIC_PLUGIN_ID:-}" ]]; then
  AGENT_AUTO_REGISTER_RESOURCES=""
  : "${AGENT_IDLE_TIMEOUT:=300s}"
  export AGENT_AUTO_REGISTER_ELASTIC_AGENT_ID AGENT_AUTO_REGISTER_ELASTIC_PLUGIN_ID AGENT_IDLE_TIMEOUT
  echo "→ Elastic agent mode: plugin=${AGENT_AUTO_REGISTER_ELASTIC_PLUGIN_ID} id=${AGENT_AUTO_REGISTER_ELASTIC_AGENT_ID} idle_timeout=${AGENT_IDLE_TIMEOUT}"
fi

# ── CI mode (symlink name or env) ─────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == *run-ci-agent* ]] || [[ "${AGENT_CI_MODE:-}" == "1" ]]; then
  AGENT_WORK_DIR="${AGENT_WORK_DIR:-/tmp/ex_gocd_ci_work}"
  AGENT_AUTO_REGISTER_RESOURCES="${AGENT_AUTO_REGISTER_RESOURCES:-elixir,postgres}"
  AGENT_HOSTNAME="${AGENT_HOSTNAME:-ci-agent}"
else
  AGENT_WORK_DIR="${AGENT_WORK_DIR:-$AGENT_DIR/work}"
fi
mkdir -p "$AGENT_WORK_DIR"

export AGENT_SERVER_URL="${AGENT_SERVER_URL:-http://localhost:4000}"
export AGENT_WORK_DIR="$AGENT_WORK_DIR"
# Only export AGENT_UUID if explicitly provided (avoid empty-string override)
if [[ -n "${AGENT_UUID:-}" ]]; then
  export AGENT_UUID="$AGENT_UUID"
fi
export EX_GOCD_DEMO_COOKIE="${EX_GOCD_DEMO_COOKIE:-ex-gocd-demo-cookie}"

# ── Kill stale agent (PID file named {uuid}.pid) ─────────────────────
AGENT_RUN_DIR="$AGENT_WORK_DIR/agent"
for pidfile in "$AGENT_RUN_DIR"/*.pid; do
  [[ -f "$pidfile" ]] || continue
  OLD_PID=$(cat "$pidfile" 2>/dev/null || true)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "→ Killing stale agent (PID $OLD_PID, pidfile $(basename "$pidfile"))"
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$pidfile"
done

# ── Clean up old per-PID work directories (from pre-UUID era) ─────────
for pid_dir in "$AGENT_WORK_DIR"/[0-9]*/; do
  [[ -d "$pid_dir" ]] || continue
  echo "→ Removing old per-PID work dir: $pid_dir"
  rm -rf "$pid_dir"
done

# ── OpenTelemetry → Collector → Jaeger (dev default, opt-out via OTEL_TRACES_EXPORTER=none) ──
export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-otlp}"
if [[ "$OTEL_TRACES_EXPORTER" == "otlp" ]]; then
  export OTEL_SERVICE_NAME="${AGENT_OTEL_SERVICE_NAME:-${OTEL_SERVICE_NAME:-gocd-agent}}"
  export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-localhost:4318}"
fi

# ── Show what we're about to start ────────────────────────────────────
echo "──────────────────────────────────────────────────────────────────"
echo "GoCD Agent → ${AGENT_SERVER_URL}"
echo "  UUID:      ${AGENT_UUID:-<will generate fresh>}"
echo "  Work dir:  $AGENT_WORK_DIR"
echo "  Tracing:   ${OTEL_TRACES_EXPORTER:-none}"
echo "──────────────────────────────────────────────────────────────────"

# ── Start agent ────────────────────────────────────────────────────────
cd "$AGENT_DIR"
exec go run .
