#!/bin/bash
# Unified Cypress E2E runner — works identically locally and in CI.
# Uses mix phx.server (no Docker) with USE_MOCK_DATA=true.
#
# Usage:
#   ./scripts/run_cypress.sh              # port 4001, chrome
#   ./scripts/run_cypress.sh --port 4000  # custom port
#   ./scripts/run_cypress.sh --help       # show help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# ── Defaults ─────────────────────────────────────────────────────────────
CYPRESS_PORT=4001
BROWSER="chrome"
CYPRESS_DB="ex_gocd_cypress"
DB_URL="ecto://postgres:postgres@localhost/${CYPRESS_DB}"

# ── Parse args ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) CYPRESS_PORT="$2"; shift 2 ;;
    --browser) BROWSER="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--port PORT] [--browser BROWSER]"
      echo ""
      echo "  --port     Port for Phoenix server (default: 4001)"
      echo "  --browser  Cypress browser   (default: chrome)"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}=== $*${NC}"; }
pass() { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }

# ── Cleanup ──────────────────────────────────────────────────────────────
cleanup() {
  log "Cleaning up..."
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ── Stop anything on our port ────────────────────────────────────────────
log "Stopping any existing server on port $CYPRESS_PORT"
lsof -ti ":$CYPRESS_PORT" | xargs kill -9 2>/dev/null || true
sleep 1

# ── Setup DB ─────────────────────────────────────────────────────────────
log "Setting up Cypress DB: $CYPRESS_DB"
MIX_ENV=dev USE_MOCK_DATA=true DATABASE_URL="$DB_URL" \
  mix ecto.drop --quiet 2>/dev/null || true
MIX_ENV=dev USE_MOCK_DATA=true DATABASE_URL="$DB_URL" \
  mix ecto.create --quiet
MIX_ENV=dev USE_MOCK_DATA=true DATABASE_URL="$DB_URL" \
  mix ecto.migrate --quiet
MIX_ENV=dev USE_MOCK_DATA=true DATABASE_URL="$DB_URL" \
  mix run priv/repo/seeds.exs
pass "DB ready"

# ── Start server ─────────────────────────────────────────────────────────
log "Starting Phoenix server on port $CYPRESS_PORT"
USE_MOCK_DATA=true DATABASE_URL="$DB_URL" PORT="$CYPRESS_PORT" \
  LOG_LEVEL=info \
  mix phx.server &
SERVER_PID=$!

# ── Wait for server ──────────────────────────────────────────────────────
log "Waiting for server..."
server_ready=false
for i in $(seq 1 60); do
  if curl -s -o /dev/null -w "%{http_code}" \
       "http://localhost:$CYPRESS_PORT/materials" 2>/dev/null | grep -q 200; then
    pass "Server ready on port $CYPRESS_PORT (attempt $i)"
    server_ready=true
    break
  fi
  printf "  waiting... (%d/60)\n" "$i"
  sleep 2
done

if [ "$server_ready" = false ]; then
  fail "Server failed to start within 120 seconds"
  exit 1
fi

# ── Run Cypress ──────────────────────────────────────────────────────────
log "Running Cypress tests (browser: $BROWSER)"
mkdir -p cypress/results

exit_code=0
CYPRESS_BASE_URL="http://localhost:$CYPRESS_PORT" \
  npx cypress run --browser "$BROWSER" || exit_code=$?

if [ "$exit_code" -eq 0 ]; then
  pass "Cypress tests passed"
else
  fail "Cypress tests failed (exit $exit_code)"
fi

log "Done"
exit "$exit_code"
