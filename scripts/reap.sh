#!/usr/bin/env bash
# reap.sh — Kill all ex_gocd & plugin BEAM processes and clean EPMD.
# Safe: only matches processes running from this project or with known node names.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KILLED=0

echo "=== Reaping ex_gocd cluster processes ==="
echo ""

# ── Kill by node name pattern (via ps) ────────────────────────────────
NODE_PATTERNS=(
  'ex_gocd@'
  'ex_gocd2@'
  'regional_affinity@'
  'corp_policy@'
  'simple_org_chart@'
)

for pattern in "${NODE_PATTERNS[@]}"; do
  pids=$(ps aux | grep "[b]eam.*-name ${pattern}" | awk '{print $2}' || true)
  for pid in $pids; do
    if [ -n "$pid" ]; then
      echo "  killing beam (${pattern}…) PID=$pid"
      kill -9 "$pid" 2>/dev/null || true
      KILLED=$((KILLED + 1))
    fi
  done
done

# ── Kill by working directory match ───────────────────────────────────
# Catch any beam running mix phx.server or mix run from our dirs
for dir in "$PROJECT_ROOT" "$PROJECT_ROOT/plugins/managed/"*; do
  [ -d "$dir" ] || continue
  pids=$(ps aux | grep "[b]eam.*-S mix" | grep "$dir" | awk '{print $2}' || true)
  for pid in $pids; do
    if [ -n "$pid" ]; then
      echo "  killing beam (cwd=$dir) PID=$pid"
      kill -9 "$pid" 2>/dev/null || true
      KILLED=$((KILLED + 1))
    fi
  done
done

# ── Kill leftover mac_listener (file_system watchers) ─────────────────
listener_pids=$(ps aux | grep "[m]ac_listener" | grep "$PROJECT_ROOT" | awk '{print $2}' || true)
for pid in $listener_pids; do
  if [ -n "$pid" ]; then
    echo "  killing mac_listener PID=$pid"
    kill -9 "$pid" 2>/dev/null || true
    KILLED=$((KILLED + 1))
  fi
done

# ── Clean EPMD ────────────────────────────────────────────────────────
echo ""
if epmd -names 2>/dev/null | grep -qE '(ex_gocd|regional_affinity|corp_policy|simple_org_chart)'; then
  echo "  stale EPMD entries found, waiting for cleanup..."
  sleep 2
fi

# EPMD auto-cleans dead nodes within ~60s. Force-check:
remaining=$(epmd -names 2>/dev/null | grep -cE '(ex_gocd|regional_affinity|corp_policy|simple_org_chart)' || true)
if [ "${remaining:-0}" -gt 0 ]; then
  echo "  ${remaining} stale EPMD entries still present (will clear on next start)"
fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
if [ "$KILLED" -gt 0 ]; then
  echo -e "${GREEN}Reaped ${KILLED} process(es).${NC}"
else
  echo "No ex_gocd processes found running."
fi
echo ""
echo "EPMD state:"
epmd -names 2>/dev/null || echo "  epmd not running"
echo ""
echo "Ready for: process-compose -f process-compose.cluster.yaml up"
