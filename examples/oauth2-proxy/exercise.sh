#!/usr/bin/env bash
# =============================================================================
# Exercise the self-contained OAuth2-Proxy + ExGoCD demo
#
# Starts a complete stack: PostgreSQL + ExGoCD server + oauth2-proxy.
# The ExGoCD server has EX_GOCD_AUTO_CREATE_USERS=true + EX_GOCD_ADMIN_USERS set.
#
# Milestones:
#   1. ExGoCD server healthy (port 4004)
#   2. oauth2-proxy healthy (port 4180)
#   3. Basic auth through proxy → HTTP 200
#   4. admin@exgocd.local auto-created with admin role
#   5. User management APIs work
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$SCRIPT_DIR/../docker/oauth2-proxy-demo"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yaml"

SERVER_URL="http://localhost:4004"
PROXY_URL="http://localhost:4180"
PROJECT="exgocd-oauth2-demo"

TIMEOUT_SERVER=120
TIMEOUT_PROXY=30
POLL_INTERVAL=2

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

passed=0
failed=0

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

teardown() {
  banner "Teardown"
  log "Stopping all services..."
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT" down -v 2>&1 | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║   OAuth2-Proxy + ExGoCD Demo (Self-Contained)                 ║"
  echo "║   $(date)                                       ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  for cmd in docker curl; do
    if ! command -v "$cmd" &>/dev/null; then
      err "$cmd is required but not found"; exit 1
    fi
  done

  if [ ! -f "$COMPOSE_FILE" ]; then
    err "Compose file not found: $COMPOSE_FILE"; exit 1
  fi

  # ── Start full stack ───────────────────────────────────────────────────
  banner "Start: PostgreSQL + ExGoCD + oauth2-proxy + smtp4dev"
  log "Bringing up all services..."
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT" build -q > /dev/null
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT" up -d > /dev/null

  # ── M1: Server healthy ─────────────────────────────────────────────────
  banner "Milestone 1: ExGoCD server healthy"
  if ! wait_for_http "${SERVER_URL}/api/version" $TIMEOUT_SERVER "ExGoCD server"; then
    failed=$((failed + 1)); teardown; print_summary; exit 1
  fi
  log "  ✓ Server running at ${SERVER_URL}"
  passed=$((passed + 1))

  # ── M2: oauth2-proxy healthy ───────────────────────────────────────────
  banner "Milestone 2: oauth2-proxy healthy"
  if ! wait_for_http "${PROXY_URL}/oauth2/sign_in" $TIMEOUT_PROXY "oauth2-proxy"; then
    failed=$((failed + 1)); teardown; print_summary; exit 1
  fi
  log "  ✓ Proxy sign-in at ${PROXY_URL}"
  passed=$((passed + 1))

  # ── M3: Basic auth through proxy ───────────────────────────────────────
  banner "Milestone 3: Authenticate via proxy"
  log "Testing basic auth as admin@exgocd.local through proxy..."

  if curl -sf -u "admin@exgocd.local:admin123" \
       -o /dev/null -w '%{http_code}' \
       "${PROXY_URL}/api/version" 2>/dev/null | grep -q "200"; then
    log "  ✓ Proxy auth succeeds (HTTP 200)"
    passed=$((passed + 1))
  else
    err "  ✗ Proxy auth failed"
    failed=$((failed + 1)); teardown; print_summary; exit 1
  fi

  # ── M4: User auto-created ──────────────────────────────────────────────
  banner "Milestone 4: User auto-creation"
  log "Triggering auto-creation via browser endpoint through proxy..."
  # AuthHeaderPlug runs in the :browser pipeline, so we need to hit a
  # browser endpoint (/pipelines) to trigger user auto-creation.
  curl -sf -u "admin@exgocd.local:admin123" "${PROXY_URL}/pipelines" > /dev/null 2>&1
  sleep 2

  local user_resp
  user_resp=$(curl -sf "${SERVER_URL}/api/users/admin@exgocd.local" 2>/dev/null || echo '{"not_found":true}')

  # Parse JSON with python3 for precise assertions
  local admin_username admin_roles admin_status
  admin_username=$(echo "$user_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('username',''))" 2>/dev/null)
  admin_roles=$(echo "$user_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(d.get('roles',[])))" 2>/dev/null)
  admin_status=$(echo "$user_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null)

  if [ "$admin_username" = "admin@exgocd.local" ] && [ "$admin_status" = "Active" ]; then
    log "  ✓ admin@exgocd.local auto-created (status=$admin_status, roles=$admin_roles)"
    if echo "$admin_roles" | grep -qw "admin"; then
      log "  ✓ admin role confirmed"
    else
      err "  ✗ admin role missing (got: $admin_roles)"
      failed=$((failed + 1))
    fi
    passed=$((passed + 1))
  else
    err "  ✗ User not auto-created or invalid. username=$admin_username status=$admin_status"
    failed=$((failed + 1))
  fi

  # Also create dev user
  curl -sf -u "dev@exgocd.local:dev123" "${PROXY_URL}/pipelines" > /dev/null 2>&1
  sleep 1

  local dev_username dev_roles
  dev_resp=$(curl -sf "${SERVER_URL}/api/users/dev@exgocd.local" 2>/dev/null || echo '{}')
  dev_username=$(echo "$dev_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('username',''))" 2>/dev/null)
  dev_roles=$(echo "$dev_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(d.get('roles',[])))" 2>/dev/null)

  if [ "$dev_username" = "dev@exgocd.local" ]; then
    log "  ✓ dev@exgocd.local auto-created (roles=$dev_roles)"
  else
    err "  ✗ dev@exgocd.local not auto-created"
    failed=$((failed + 1))
  fi

  # ── M5: User management APIs ───────────────────────────────────────────
  banner "Milestone 5: User management APIs"

  local list_resp
  list_resp=$(curl -sf "${SERVER_URL}/api/users" 2>/dev/null || echo '{"users":[]}')
  local user_count
  user_count=$(echo "$list_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('users',[])))" 2>/dev/null)

  # Verify both users are in the list with correct roles
  local admin_in_list dev_in_list
  admin_in_list=$(echo "$list_resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
users=[u for u in d.get('users',[]) if u.get('username')=='admin@exgocd.local' and 'admin' in u.get('roles',[])]
print('yes' if users else 'no')
" 2>/dev/null)
  dev_in_list=$(echo "$list_resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
users=[u for u in d.get('users',[]) if u.get('username')=='dev@exgocd.local']
print('yes' if users else 'no')
" 2>/dev/null)

  if [ "${user_count:-0}" -ge 2 ] && [ "$admin_in_list" = "yes" ] && [ "$dev_in_list" = "yes" ]; then
    log "  ✓ GET /api/users: ${user_count} users, both present with correct roles"
    passed=$((passed + 1))
  else
    err "  ✗ GET /api/users: count=$user_count admin_in_list=$admin_in_list dev_in_list=$dev_in_list"
    failed=$((failed + 1))
  fi

  # ── Teardown ────────────────────────────────────────────────────────────
  teardown
  print_summary
}

print_summary() {
  echo ""
  echo "══════════════════════════════════════════════════════════════"
  echo "  OAuth2-Proxy Demo: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}"
  echo "══════════════════════════════════════════════════════════════"
  echo ""
  [ "$failed" -gt 0 ] && exit 1
  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
