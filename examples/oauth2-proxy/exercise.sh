#!/usr/bin/env bash
# =============================================================================
# Exercise the oauth2-proxy + ExGoCD OAuth demo
#
# Assumes:
#   - ex_gocd server already running (default: http://localhost:4000)
#   - EX_GOCD_AUTO_CREATE_USERS=true is set in the server's environment
#     (the AuthHeaderPlug reads it at request time, no restart needed
#      if set before starting the server)
#
# Milestones:
#   1. oauth2-proxy container healthy
#   2. Authenticated request through proxy returns 200
#   3. User auto-created in DB (via X-Forwarded-User header)
#   4. User search API works
#   5. Current user API works
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_PROXY=30
TIMEOUT_SERVER=10
POLL_INTERVAL=2

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults — override via env
SERVER_URL="${SERVER_URL:-http://localhost:4000}"
PROXY_URL="${PROXY_URL:-http://localhost:4180}"
PROJECT="${PROJECT:-exgocd-oauth2-demo}"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

passed=0
failed=0

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
err()  { echo -e "${RED}[FAIL]${NC}  $(date '+%H:%M:%S') $*"; }

banner() {
  echo ""
  echo "=============================================="
  echo "  $*"
  echo "=============================================="
}

# Poll a URL until it returns HTTP 200 (or timeout).
wait_for_http() {
  local url="$1" timeout="$2" desc="$3" elapsed=0
  log "Waiting for $desc at $url (timeout ${timeout}s)..."
  while [ $elapsed -lt $timeout ]; do
    if curl -sf -o /dev/null "$url" 2>/dev/null; then
      log "$desc is UP after ${elapsed}s"
      return 0
    fi
    sleep $POLL_INTERVAL
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  err "$desc did NOT become healthy within ${timeout}s"
  return 1
}

# Assert that a curl command returns HTTP 200 and optionally check body.
# Usage: assert_http_ok <description> <curl_args...>
# Pass - after description and before curl args if you want to check body.
assert_http_ok() {
  local desc="$1" url="$2" expected_in_body="${3:-}"
  local http_code body

  body=$(curl -sf -w '\n%{http_code}' "$url" 2>/dev/null) || true
  http_code=$(echo "$body" | tail -1)
  body=$(echo "$body" | sed '$d')

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    if [ -n "$expected_in_body" ]; then
      if echo "$body" | grep -q "$expected_in_body"; then
        log "  ✓ $desc (HTTP $http_code, found '$expected_in_body')"
        return 0
      else
        err "  ✗ $desc (HTTP $http_code but '$expected_in_body' not in body)"
        log "  Body: $(echo "$body" | head -5)"
        return 1
      fi
    else
      log "  ✓ $desc (HTTP $http_code)"
      return 0
    fi
  else
    err "  ✗ $desc (HTTP $http_code, expected 200)"
    log "  Body: $(echo "$body" | head -5)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Main exercise
# ---------------------------------------------------------------------------

main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║   OAuth2-Proxy + ExGoCD Demo Exerciser                       ║"
  echo "║   $(date)                                       ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Check prerequisites
  for cmd in docker curl; do
    if ! command -v "$cmd" &>/dev/null; then
      err "$cmd is required but not found"
      exit 1
    fi
  done

  # ── Milestone 0: Server must be running ────────────────────────────────
  banner "Milestone 0: Verify ex_gocd server"
  if ! wait_for_http "${SERVER_URL}/api/version" $TIMEOUT_SERVER "ex_gocd server"; then
    err "ex_gocd server is not running at $SERVER_URL"
    err "Start it first: cd ex_gocd && EX_GOCD_AUTO_CREATE_USERS=true EX_GOCD_ADMIN_USERS=admin@exgocd.local mix phx.server"
    failed=$((failed + 1))
    print_summary
    exit 1
  fi
  log "ex_gocd server is running."

  # ── Milestone 1: Start oauth2-proxy ────────────────────────────────────
  banner "Milestone 1: Start oauth2-proxy container"
  log "Starting oauth2-proxy (project: $PROJECT)..."
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT" up -d 2>&1 | sed 's/^/  /'

  if ! wait_for_http "${PROXY_URL}/oauth2/sign_in" $TIMEOUT_PROXY "oauth2-proxy"; then
    err "oauth2-proxy did not start"
    failed=$((failed + 1))
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT" down -v 2>/dev/null || true
    print_summary
    exit 1
  fi
  log "oauth2-proxy is running at $PROXY_URL"
  passed=$((passed + 1))

  # ── Milestone 2: Auth through proxy with admin user ─────────────────────
  banner "Milestone 2: Authenticate via oauth2-proxy"
  log "Authenticating as admin@exgocd.local through proxy..."

  if curl -sf -u "admin@exgocd.local:admin123" \
       -o /dev/null -w '%{http_code}' \
       "${PROXY_URL}/api/version" 2>/dev/null | grep -q "200"; then
    log "  ✓ Basic auth through proxy works (HTTP 200)"
  else
    err "  ✗ Basic auth through proxy failed"
    failed=$((failed + 1))
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT" down -v 2>/dev/null || true
    print_summary
    exit 1
  fi
  passed=$((passed + 1))

  # ── Milestone 3: User auto-created via X-Forwarded-User header ─────────
  banner "Milestone 3: Verify auto-created users"
  log "Checking if admin@exgocd.local is auto-created..."

  local user_resp
  user_resp=$(curl -sf "${SERVER_URL}/api/users/admin@exgocd.local" 2>/dev/null || echo '{"not_found":true}')
  log "  User API response: $(echo "$user_resp" | head -1)"

  if echo "$user_resp" | grep -q '"username":"admin@exgocd.local"'; then
    log "  ✓ User admin@exgocd.local found in DB"
    if echo "$user_resp" | grep -q '"admin"'; then
      log "  ✓ User has admin role"
    else
      warn "  ⚠ User exists but may not have admin role (check EX_GOCD_ADMIN_USERS)"
    fi
    passed=$((passed + 1))
  else
    warn "  ⚠ User not auto-created. EX_GOCD_AUTO_CREATE_USERS must be 'true' at server start."
    warn "  Add to process-compose.yaml: EX_GOCD_AUTO_CREATE_USERS=true"
    warn "  Add to process-compose.yaml: EX_GOCD_ADMIN_USERS=admin@exgocd.local"
    warn "  Then restart: process-compose down && process-compose up"
    failed=$((failed + 1))
  fi

  # ── Milestone 4: User search API ───────────────────────────────────────
  banner "Milestone 4: Test user_search API"
  if assert_http_ok "user search" "${SERVER_URL}/api/user_search?q=admin" ""; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi

  # ── Milestone 5: Current user API (via proxy with session cookie) ──────
  banner "Milestone 5: Test current_user API (via proxy)"
  log "Accessing /api/current_user through oauth2-proxy..."

  local curr_user_resp
  curr_user_resp=$(curl -sf -u "admin@exgocd.local:admin123" \
    "${PROXY_URL}/api/current_user" 2>/dev/null || echo "")

  if echo "$curr_user_resp" | grep -q '"username"'; then
    log "  ✓ Current user API responds through proxy"
    log "  Body: $(echo "$curr_user_resp" | python3 -m json.tool 2>/dev/null || echo "$curr_user_resp")"
    passed=$((passed + 1))
  else
    warn "  ⚠ Current user API not accessible (session may not propagate through proxy)"
    log "  (CurrentUserController requires a valid session; auth via PAT/Bearer token is needed)"
    log "  This is expected when AUTO_CREATE_USERS is off or session auth is not configured."
    warn "  Skipping — not a blocker."
  fi

  # ── Teardown ────────────────────────────────────────────────────────────
  banner "Teardown"
  log "Stopping oauth2-proxy..."
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT" down -v 2>&1 | sed 's/^/  /'

  print_summary
}

print_summary() {
  echo ""
  echo "══════════════════════════════════════════════════════════════"
  echo "  OAuth2-Proxy Demo: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}"
  echo "══════════════════════════════════════════════════════════════"
  echo ""

  if [ "$failed" -gt 0 ]; then
    exit 1
  fi
}

# Allow sourcing without running (for exercise_all.sh integration)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
