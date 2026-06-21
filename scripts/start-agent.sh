#!/usr/bin/env bash
# ── ex_gocd Go Agent ───────────────────────────────────────────────────
# Starts the Go agent with PID file management. Auto-detects CI mode when
# called as run-ci-agent.sh or with AGENT_CI_MODE=1.
#
# Usage:
#   ./scripts/start-agent.sh              # default mode (work dir: agent/work)
#   AGENT_CI_MODE=1 ./scripts/start-agent.sh  # CI mode
#   ./scripts/run-ci-agent.sh             # symlink → CI mode
#
# Env vars: AGENT_SERVER_URL, AGENT_WORK_DIR, AGENT_AUTO_REGISTER_RESOURCES,
#           AGENT_AUTO_REGISTER_ENVIRONMENTS, AGENT_AUTO_REGISTER_KEY,
#           AGENT_HOSTNAME, EX_GOCD_DEMO_COOKIE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT/agent"
PIDFILE="/tmp/ex_gocd_agent.pid"

# ── Kill stale agent if PID file exists from previous run ──────────────
if [[ -f "$PIDFILE" ]]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Killing stale agent (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
fi

# ── CI mode (symlink name or env) ──────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == *run-ci-agent* ]] || [[ "${AGENT_CI_MODE:-}" == "1" ]]; then
  AGENT_WORK_DIR="${AGENT_WORK_DIR:-/tmp/ex_gocd_ci_work}"
  AGENT_AUTO_REGISTER_RESOURCES="${AGENT_AUTO_REGISTER_RESOURCES:-elixir,postgres}"
  AGENT_HOSTNAME="${AGENT_HOSTNAME:-ci-agent}"
  mkdir -p "$AGENT_WORK_DIR"
  echo "CI Agent → ${AGENT_SERVER_URL:-http://localhost:4000}"
  echo "  Resources:  $AGENT_AUTO_REGISTER_RESOURCES"
  echo "  Work dir:   $AGENT_WORK_DIR"
  echo "  Name:       $AGENT_HOSTNAME"
else
  AGENT_WORK_DIR="${AGENT_WORK_DIR:-$AGENT_DIR/work}"
  mkdir -p "$AGENT_WORK_DIR"
  echo "Agent → ${AGENT_SERVER_URL:-http://localhost:4000} (work dir: $AGENT_WORK_DIR)"
fi

export AGENT_SERVER_URL="${AGENT_SERVER_URL:-http://localhost:4000}"
export AGENT_WORK_DIR="$AGENT_WORK_DIR"
export EX_GOCD_DEMO_COOKIE="${EX_GOCD_DEMO_COOKIE:-ex-gocd-demo-cookie}"

# ── Start agent ────────────────────────────────────────────────────────
cd "$AGENT_DIR"
echo $$ > "$PIDFILE"
trap 'rm -f $PIDFILE' EXIT
exec go run .
