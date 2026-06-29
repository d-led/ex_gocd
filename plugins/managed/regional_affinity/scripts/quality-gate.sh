#!/bin/bash
# Quality Gate for extracted plugin OTP apps.
# Run from the plugin directory root (e.g., plugins/managed/regional_affinity/).
# Exit code 0 = all checks pass.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

die() { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }
pass_step() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail_step() { echo -e "${RED}[FAIL]${NC} $1"; die "Plugin quality gate halted."; }

echo ""
echo "=== Plugin: $(basename "$PWD") ==="

# ── Deps ──
echo "--- mix deps.get ---"
mix deps.get 2>&1 | tail -1

# ── Format ──
echo "--- mix format --check-formatted ---"
mix format --check-formatted 2>&1 && pass_step "format" || fail_step "format — unformatted files"

# ── Compile ──
echo "--- mix compile --warnings-as-errors ---"
mix compile --warnings-as-errors 2>&1 && pass_step "compile" || fail_step "compile — warnings found"

# ── Tests ──
echo "--- mix test ---"
mix test 2>&1 | tail -3
MIX_TEST_EXIT=${PIPESTATUS[0]}
if [ $MIX_TEST_EXIT -eq 0 ]; then
  pass_step "tests"
else
  fail_step "tests — failures found"
fi

# ── Sobelow security scan ──
echo "--- mix sobelow ---"
mix sobelow 2>&1 | tail -1 && pass_step "sobelow" || fail_step "sobelow — security findings"

# ── Credo ──
if mix credo --format=oneline 2>&1; then
  pass_step "credo"
else
  fail_step "credo — suggestions found"
fi

echo ""
echo "=== Plugin $(basename "$PWD"): ALL PASS ==="
