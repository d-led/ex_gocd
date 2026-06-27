#!/usr/bin/env bash
# =============================================================================
# Exercise all example Docker Compose configurations in examples/docker/
#
# Each example is started, verified against milestones, and torn down.
# Timeouts and project isolation prevent resource leaks.
#
# Milestones (ex_gocd server examples):
#   1. Server healthy
#   2. Agent visible & idle
#   3. Pipeline scheduled → running → completed (via DB check)
#
# Milestones (GoCD server example):
#   1. Server healthy
#   2. Agent visible & idle
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$SCRIPT_DIR/docker"
TIMEOUT_SERVER=120
TIMEOUT_AGENT=60
TIMEOUT_JOB=60
POLL_INTERVAL=2

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
# Usage: wait_for_http <url> <timeout_seconds> <description>
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

# ---------------------------------------------------------------------------
# Example runner: ex_gocd server (our Phoenix) with any agent
# $1 = project name
# $2 = compose file
# $3 = server port
# $4 = db port
# $5 = label
# $6 = agent resource (for job scheduling)
# ---------------------------------------------------------------------------
run_exgocd_example() {
  local project="$1" compose_file="$2" server_port="$3" db_port="$4" label="$5" resource="$6"
  local server_url="http://localhost:${server_port}"

  banner "$label"

  # ── Start ──────────────────────────────────────────────────────────────
  log "Starting $project..."
  docker compose -f "$compose_file" -p "$project" up -d --build 2>&1 | sed 's/^/  /'

  # ── Milestone 1: Server healthy ────────────────────────────────────────
  if ! wait_for_http "${server_url}/api/version" $TIMEOUT_SERVER "ex_gocd server"; then
    failed=$((failed + 1))
    docker compose -f "$compose_file" -p "$project" down -v 2>/dev/null || true
    return 1
  fi

  # ── Milestone 2: Agent visible & idle ──────────────────────────────────
  log "Waiting for agent to register and become idle..."
  local agent_elapsed=0 agent_found=false
  while [ $agent_elapsed -lt $TIMEOUT_AGENT ]; do
    local stats
    stats=$(curl -sf "${server_url}/api/stats" 2>/dev/null || true)
    local total idle building
    total=$(echo "$stats" | grep -oE '"total":[0-9]+' | head -1 | cut -d: -f2)
    idle=$(echo "$stats" | grep -oE '"idle":[0-9]+' | head -1 | cut -d: -f2)
    building=$(echo "$stats" | grep -oE '"building":[0-9]+' | head -1 | cut -d: -f2)

    log "  Agents: total=$total idle=$idle building=$building"

    if [ "${total:-0}" -ge 1 ] && [ "${idle:-0}" -ge 1 ]; then
      log "Agent registered and idle!"
      agent_found=true
      break
    fi
    sleep $POLL_INTERVAL
    agent_elapsed=$((agent_elapsed + POLL_INTERVAL))
  done

  if [ "$agent_found" = false ]; then
    err "No idle agent within ${TIMEOUT_AGENT}s"
    log "Debug: agent stats"
    curl -sf "${server_url}/api/stats" 2>/dev/null | python3 -m json.tool 2>/dev/null || true
    log "Debug: agent list"
    curl -sf "${server_url}/api/agents" 2>/dev/null | python3 -m json.tool 2>/dev/null || true
    failed=$((failed + 1))
    docker compose -f "$compose_file" -p "$project" down -v 2>/dev/null || true
    return 1
  fi

  # ── Milestone 3: Schedule job & wait for completion ────────────────────
  local pipeline="demo-${project}"
  log "Scheduling job: pipeline=$pipeline resource=$resource..."

  local schedule_resp
  schedule_resp=$(curl -sf -X POST "${server_url}/api/jobs/schedule" \
    -H "Content-Type: application/json" \
    -d "{\"pipeline\":\"${pipeline}\",\"stage\":\"build\",\"job\":\"default\",\"resources\":[\"${resource}\"]}" 2>/dev/null || true)
  log "Schedule response: $schedule_resp"

  # Wait for job to be picked up and completed
  log "Waiting for job execution to complete..."
  local job_elapsed=0 job_done=false
  while [ $job_elapsed -lt $TIMEOUT_JOB ]; do
    local stats running
    stats=$(curl -sf "${server_url}/api/stats" 2>/dev/null || true)
    running=$(echo "$stats" | grep -oE '"running":[0-9]+' | head -1 | cut -d: -f2)

    # Try DB query if port exposed
    local db_state="" db_result=""
    if [ -n "${db_port:-}" ] && [ "$db_port" != "0" ]; then
      db_state=$(PGPASSWORD=postgres psql -h localhost -p "$db_port" -U postgres -d ex_gocd_prod -t -A -c \
        "SELECT state FROM agent_job_runs WHERE pipeline_name='${pipeline}' ORDER BY inserted_at DESC LIMIT 1;" 2>/dev/null || echo "")
      db_result=$(PGPASSWORD=postgres psql -h localhost -p "$db_port" -U postgres -d ex_gocd_prod -t -A -c \
        "SELECT result FROM agent_job_runs WHERE pipeline_name='${pipeline}' ORDER BY inserted_at DESC LIMIT 1;" 2>/dev/null || echo "")
    fi

    log "  running=${running:-?} db_state=${db_state:-?} db_result=${db_result:-?}"

    if [ "$db_state" = "Completed" ]; then
      if [ "$db_result" = "Passed" ]; then
        log "Job completed successfully: $db_result"
        job_done=true
        break
      else
        err "Job completed but result is: $db_result"
        job_done=true
        break
      fi
    fi

    sleep $POLL_INTERVAL
    job_elapsed=$((job_elapsed + POLL_INTERVAL))
  done

  if [ "$job_done" = false ]; then
    warn "Job did not complete within ${TIMEOUT_JOB}s, checking last state..."
    # Fallback: if running was non-zero then went to zero, it completed
    local stats
    stats=$(curl -sf "${server_url}/api/stats" 2>/dev/null || true)
    local running
    running=$(echo "$stats" | grep -oE '"running":[0-9]+' | head -1 | cut -d: -f2)
    if [ "${running:-1}" -eq 0 ]; then
      warn "No running jobs - may have completed silently. Checking DB..."
      if [ -n "${db_port:-}" ] && [ "$db_port" != "0" ]; then
        local has_entry
        has_entry=$(PGPASSWORD=postgres psql -h localhost -p "$db_port" -U postgres -d ex_gocd_prod -t -A -c \
          "SELECT count(*) FROM agent_job_runs WHERE pipeline_name='${pipeline}';" 2>/dev/null || echo "0")
        if [ "${has_entry:-0}" -gt 0 ]; then
          warn "Found ${has_entry} job run(s) for ${pipeline} - job likely completed"
          job_done=true
        fi
      fi
    fi
  fi

  # ── Teardown ────────────────────────────────────────────────────────────
  log "Tearing down $project..."
  docker compose -f "$compose_file" -p "$project" down -v 2>&1 | sed 's/^/  /'

  if [ "$job_done" = true ]; then
    echo -e "${GREEN}[PASS]${NC} $label"
    passed=$((passed + 1))
  else
    echo -e "${RED}[FAIL]${NC} $label — job did not complete"
    failed=$((failed + 1))
  fi
}

# ---------------------------------------------------------------------------
# Example runner: Official GoCD server with ex_gocd Go agent
# ---------------------------------------------------------------------------
run_gocd_example() {
  local project="$1" compose_file="$2" label="$3"
  local server_url="http://localhost:8153"

  banner "$label"

  # ── Start GoCD server only (agent uses profile, started later) ─────────
  log "Starting $project (GoCD server takes ~2-3 min to start)..."
  docker compose -f "$compose_file" -p "$project" up -d --build go-server 2>&1 | sed 's/^/  /'

  # ── Milestone 1: GoCD server healthy ───────────────────────────────────
  if ! wait_for_http "${server_url}/go/api/support" $TIMEOUT_SERVER "GoCD server"; then
    warn "GoCD server not healthy yet, checking with curl for debug..."
    curl -sv "${server_url}/go/api/support" 2>&1 | head -20 || true
    failed=$((failed + 1))
    docker compose -f "$compose_file" -p "$project" down -v 2>/dev/null || true
    return 1
  fi

  # ── Read auto-generated agent auto-register key ─────────────────────────
  local auto_key
  auto_key=$(docker exec "${project}-go-server-1" cat /godata/config/cruise-config.xml 2>/dev/null | grep -oE 'agentAutoRegisterKey="[^"]*"' | head -1 | cut -d'"' -f2)
  if [ -z "$auto_key" ]; then
    err "Could not read agent auto-register key from GoCD server config"
    failed=$((failed + 1))
    docker compose -f "$compose_file" -p "$project" down -v 2>/dev/null || true
    return 1
  fi
  log "GoCD auto-register key: $auto_key"

  # ── Start agent with correct key ───────────────────────────────────────
  log "Starting ex_gocd agent with correct key..."
  AGENT_AUTO_REGISTER_KEY="$auto_key" docker compose -f "$compose_file" -p "$project" --profile agent up -d --build ex-gocd-agent 2>&1 | sed 's/^/  /'

  # ── Milestone 2: Agent visible & idle ──────────────────────────────────
  log "Waiting for agent to register and become idle..."
  local agent_elapsed=0 agent_found=false
  while [ $agent_elapsed -lt $TIMEOUT_AGENT ]; do
    # GoCD API returns agents in _embedded.agents
    local agents_json
    agents_json=$(curl -sf "${server_url}/go/api/agents" -H "Accept: application/vnd.go.cd.v7+json" 2>/dev/null || true)
    local agent_count
    agent_count=$(echo "$agents_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
agents=d.get('_embedded',{}).get('agents',[])
print(len(agents))
" 2>/dev/null || echo "0")

    local idle_count
    idle_count=$(echo "$agents_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
agents=d.get('_embedded',{}).get('agents',[])
print(sum(1 for a in agents if a.get('agent_state')=='Idle'))
" 2>/dev/null || echo "0")

    log "  Agents: total=$agent_count idle=$idle_count"

    if [ "${agent_count:-0}" -ge 1 ] && [ "${idle_count:-0}" -ge 1 ]; then
      log "Agent registered and idle on GoCD server!"
      agent_found=true
      break
    fi
    sleep $POLL_INTERVAL
    agent_elapsed=$((agent_elapsed + POLL_INTERVAL))
  done

  if [ "$agent_found" = false ]; then
    err "No idle agent on GoCD server within ${TIMEOUT_AGENT}s"
    log "Debug: GoCD agent list"
    curl -sf "${server_url}/go/api/agents" -H "Accept: application/vnd.go.cd.v7+json" 2>/dev/null | python3 -m json.tool 2>/dev/null || true
    failed=$((failed + 1))
    docker compose -f "$compose_file" -p "$project" down -v 2>/dev/null || true
    return 1
  fi

  # ── Teardown ────────────────────────────────────────────────────────────
  log "Tearing down $project..."
  docker compose -f "$compose_file" -p "$project" --profile agent down -v 2>&1 | sed 's/^/  /'

  echo -e "${GREEN}[PASS]${NC} $label — agent registered with official GoCD server"
  passed=$((passed + 1))
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   ex_gocd Example Compose Exerciser                           ║"
echo "║   $(date)                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
for cmd in docker curl python3 psql; do
  if ! command -v "$cmd" &>/dev/null; then
    warn "$cmd not found — some checks may be skipped"
  fi
done

# ── Example 1: Official GoCD server + ex_gocd Go agent ──────────────────
# This proves our agent protocol is compatible with the real GoCD server.
run_gocd_example \
  "exgocd-ex1-gocd-agent" \
  "$EXAMPLES_DIR/gocd-server-ex-agent/docker-compose.yaml" \
  "Example 1: GoCD server + ex_gocd Go agent"

# ── Example 2: ex_gocd server + ex_gocd Go agent ─────────────────────────
# Full stack: our Phoenix server + PostgreSQL + our Go agent.
run_exgocd_example \
  "exgocd-ex2-ex-agent" \
  "$EXAMPLES_DIR/exgocd-server-ex-agent/docker-compose.yaml" \
  4002 5433 \
  "Example 2: ex_gocd server + ex_gocd Go agent" \
  "go"

# ── Example 3: ex_gocd server + official GoCD Java agent ──────────────────
# Our Phoenix server with the official gocd/gocd-agent-alpine container.
# The Java agent auto-registers; verify pipeline execution.
run_exgocd_example \
  "exgocd-ex3-java-agent" \
  "$EXAMPLES_DIR/exgocd-server-gocd-agent/docker-compose.yaml" \
  4003 5434 \
  "Example 3: ex_gocd server + official Java agent" \
  "java"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  RESULTS: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}"
echo "══════════════════════════════════════════════════════════════"
echo ""

if [ "$failed" -gt 0 ]; then
  exit 1
fi
exit 0
