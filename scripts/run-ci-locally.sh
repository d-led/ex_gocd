#!/usr/bin/env bash
# ── ex_gocd local CI runner ──────────────────────────────────────────────
# Starts the Phoenix server + a GoCD agent that auto-registers and can run
# the "ex_gocd" pipeline (mix test, mix quality) locally.
#
# Prerequisites: postgres running (docker compose up -d postgres), Elixir + Go installed.
#
# Usage:
#   ./scripts/run-ci-locally.sh            # full setup: seed → server → agent
#   ./scripts/run-ci-locally.sh agent-only # just start the agent (server already running)
#   ./scripts/run-ci-locally.sh seed-only  # just seed the DB
#   ./scripts/run-ci-locally.sh trigger    # trigger the pipeline via API
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT/agent"

# ── Config ───────────────────────────────────────────────────────────────
export EX_GOCD_DEMO_COOKIE="${EX_GOCD_DEMO_COOKIE:-ex-gocd-demo-cookie}"
SERVER_URL="${AGENT_SERVER_URL:-http://localhost:4000}"
AGENT_NAME="${AGENT_HOSTNAME:-local-ci-agent}"
AGENT_RESOURCES="${AGENT_AUTO_REGISTER_RESOURCES:-elixir,postgres}"
AGENT_WORK_DIR="${AGENT_WORK_DIR:-/tmp/ex_gocd_agent_work}"

MODE="${1:-full}"

# ── Helpers ──────────────────────────────────────────────────────────────
red()   { echo -e "\033[0;31m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
cyan()  { echo -e "\033[0;36m$*\033[0m"; }

wait_for_url() {
  local url="$1" timeout="${2:-30}"
  cyan "Waiting for $url ..."
  for i in $(seq 1 "$timeout"); do
    if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -q "200\|302\|404\|403"; then
      green "$url is up"
      return 0
    fi
    sleep 1
  done
  red "$url not reachable after ${timeout}s"
  return 1
}

# ── Seed ─────────────────────────────────────────────────────────────────
do_seed() {
  cyan "Seeding database..."
  cd "$ROOT"
  mix run priv/repo/seeds.exs
  green "Seed complete"
}

# ── Server ───────────────────────────────────────────────────────────────
do_server() {
  if curl -s -o /dev/null "$SERVER_URL/pipelines" 2>/dev/null; then
    green "Server already running at $SERVER_URL"
    return 0
  fi

  cyan "Starting Phoenix server in background..."
  cd "$ROOT"
  mix phx.server > /tmp/ex_gocd_server.log 2>&1 &
  SERVER_PID=$!
  echo "$SERVER_PID" > /tmp/ex_gocd_server.pid

  # Give it a moment
  wait_for_url "$SERVER_URL/pipelines" 60 || {
    red "Server failed to start. Check /tmp/ex_gocd_server.log"
    cat /tmp/ex_gocd_server.log | tail -30
    exit 1
  }
}

# ── Agent ────────────────────────────────────────────────────────────────
do_agent() {
  cyan "Starting agent via start-agent.sh (resources: $AGENT_RESOURCES, work dir: $AGENT_WORK_DIR)..."

  export AGENT_SERVER_URL="$SERVER_URL"
  export AGENT_WORK_DIR="$AGENT_WORK_DIR"
  export AGENT_AUTO_REGISTER_RESOURCES="$AGENT_RESOURCES"
  export AGENT_AUTO_REGISTER_ENVIRONMENTS="production"
  export AGENT_HOSTNAME="$AGENT_NAME"
  export AGENT_CI_MODE=1

  exec "$ROOT/scripts/start-agent.sh"
}

# ── Trigger ──────────────────────────────────────────────────────────────
do_trigger() {
  cyan "Triggering ex_gocd pipeline..."
  curl -s -X POST "$SERVER_URL/go/api/pipelines/ex_gocd/schedule" \
    -H "Content-Type: application/json" \
    -H "Accept: application/vnd.go.cd.v1+json" \
    | python3 -m json.tool 2>/dev/null || true
  green "Trigger sent. Check $SERVER_URL/pipelines for status."
}

# ── Stop ─────────────────────────────────────────────────────────────────
do_stop() {
  if [ -f /tmp/ex_gocd_server.pid ]; then
    PID=$(cat /tmp/ex_gocd_server.pid)
    kill "$PID" 2>/dev/null && green "Server stopped (PID $PID)" || true
    rm -f /tmp/ex_gocd_server.pid
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────
echo ""
cyan "╔══════════════════════════════════════════╗"
cyan "║   ex_gocd Local CI Runner               ║"
cyan "╚══════════════════════════════════════════╝"
echo ""

case "$MODE" in
  full)
    do_seed
    do_server
    do_agent
    ;;
  agent-only)
    do_agent
    ;;
  seed-only)
    do_seed
    ;;
  trigger)
    do_trigger
    ;;
  stop)
    do_stop
    ;;
  *)
    echo "Usage: $0 {full|agent-only|seed-only|trigger|stop}"
    echo ""
    echo "  full        Seed DB, start server + agent (default)"
    echo "  agent-only  Start agent only (server already running)"
    echo "  seed-only   Seed database only"
    echo "  trigger     Trigger the ex_gocd pipeline via API"
    echo "  stop        Stop the background server"
    exit 1
    ;;
esac
