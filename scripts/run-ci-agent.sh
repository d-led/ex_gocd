#!/usr/bin/env bash
# ── ex_gocd CI agent ────────────────────────────────────────────────────
# Starts a GoCD agent that auto-registers with elixir+postgres resources
# and runs jobs from the repo root.
#
# Prerequisites: Phoenix server running (mix phx.server), postgres running.
#
# Usage:
#   ./scripts/run-ci-agent.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT/agent"

export EX_GOCD_DEMO_COOKIE="${EX_GOCD_DEMO_COOKIE:-ex-gocd-demo-cookie}"
export AGENT_SERVER_URL="${AGENT_SERVER_URL:-http://localhost:4000}"
export AGENT_WORK_DIR="${AGENT_WORK_DIR:-$ROOT}"
export AGENT_AUTO_REGISTER_RESOURCES="${AGENT_AUTO_REGISTER_RESOURCES:-elixir,postgres}"
export AGENT_AUTO_REGISTER_ENVIRONMENTS="${AGENT_AUTO_REGISTER_ENVIRONMENTS:-production}"
export AGENT_HOSTNAME="${AGENT_HOSTNAME:-ci-agent}"

echo "CI Agent → $AGENT_SERVER_URL"
echo "  Resources:  $AGENT_AUTO_REGISTER_RESOURCES"
echo "  Work dir:   $AGENT_WORK_DIR"
echo "  Name:       $AGENT_HOSTNAME"

cd "$AGENT_DIR"
exec go run .
