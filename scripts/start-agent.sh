#!/usr/bin/env bash
# ── ex_gocd Go Agent ───────────────────────────────────────────────────
# Starts the Go agent. Connects to Phoenix server at AGENT_SERVER_URL.
# Run the Phoenix server first (mix phx.server).
#
# Optional env (set before running):
#   AGENT_SERVER_URL               - server URL (default http://localhost:4000)
#   AGENT_WORK_DIR                 - working directory for jobs (default agent/work)
#   AGENT_AUTO_REGISTER_RESOURCES  - e.g. "elixir,postgres"
#   AGENT_AUTO_REGISTER_ENVIRONMENTS - e.g. "production"
#   AGENT_AUTO_REGISTER_KEY        - if server requires auto-register key
#   AGENT_HOSTNAME                 - display name (default: hostname)
#
# CI mode (when called as run-ci-agent.sh or AGENT_CI_MODE=1):
#   work dir = repo root, resources = elixir,postgres, name = ci-agent
#
# Cookie: server (dev) and agent use shared demo cookie so they always match.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT/agent"

# ── CI mode defaults ───────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == *run-ci-agent* ]] || [[ "${AGENT_CI_MODE:-}" == "1" ]]; then
  AGENT_WORK_DIR="${AGENT_WORK_DIR:-/tmp/ex_gocd_ci_work}"
  AGENT_AUTO_REGISTER_RESOURCES="${AGENT_AUTO_REGISTER_RESOURCES:-elixir,postgres}"
  AGENT_HOSTNAME="${AGENT_HOSTNAME:-ci-agent}"
  # Ensure safe work dir exists, away from our source tree
  mkdir -p "$AGENT_WORK_DIR"
  echo "CI Agent → ${AGENT_SERVER_URL:-http://localhost:4000}"
  echo "  Resources:  $AGENT_AUTO_REGISTER_RESOURCES"
  echo "  Work dir:   $AGENT_WORK_DIR"
  echo "  Name:       $AGENT_HOSTNAME"
else
  AGENT_WORK_DIR="${AGENT_WORK_DIR:-$AGENT_DIR/work}"
  echo "Starting agent → ${AGENT_SERVER_URL:-http://localhost:4000} (work dir: $AGENT_WORK_DIR)"
fi

export AGENT_SERVER_URL="${AGENT_SERVER_URL:-http://localhost:4000}"
export AGENT_WORK_DIR="$AGENT_WORK_DIR"
export EX_GOCD_DEMO_COOKIE="${EX_GOCD_DEMO_COOKIE:-ex-gocd-demo-cookie}"

cd "$AGENT_DIR"
exec go run .
