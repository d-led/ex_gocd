#!/usr/bin/env bash
set -euo pipefail

# Start the GoCD Go agent. Connects to Phoenix server at AGENT_SERVER_URL.
# Run the Phoenix server first (mix phx.server).
#
# Optional env (set before running or export in this script):
#   AGENT_SERVER_URL     - server URL (default http://localhost:4000)
#   AGENT_WORK_DIR       - working directory for jobs (default agent/work)
#   AGENT_AUTO_REGISTER_RESOURCES    - e.g. "linux,docker"
#   AGENT_AUTO_REGISTER_ENVIRONMENTS - e.g. "production"
#   AGENT_AUTO_REGISTER_KEY          - if server requires auto-register key
# Cookie is set by the server over WebSocket (setCookie); no need to set here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT/agent"
WORK_DIR="${AGENT_WORK_DIR:-$AGENT_DIR/work}"

export AGENT_SERVER_URL="${AGENT_SERVER_URL:-http://localhost:4000}"
export AGENT_WORK_DIR="$WORK_DIR"
# Shared demo cookie: server (dev) and agent use same token so they always find each other
export EX_GOCD_DEMO_COOKIE="${EX_GOCD_DEMO_COOKIE:-ex-gocd-demo-cookie}"
# Optional: uncomment to set agent resources/environments/name
# export AGENT_AUTO_REGISTER_RESOURCES="linux"
# export AGENT_AUTO_REGISTER_ENVIRONMENTS="production"
# export AGENT_HOSTNAME="my-build-agent"

cd "$AGENT_DIR"

echo "Starting agent → $AGENT_SERVER_URL (work dir: $AGENT_WORK_DIR)"
exec go run .
