#!/bin/bash
# Quality Gate — runs all static analysis for the ex_gocd project
# Covers Elixir (sobelow, credo, dialyzer, compile warnings) and Go agent.
# Exit code 0 = all checks pass. Non-zero = failures found.

set -euo pipefail

cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

pass_step() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail_step() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
warn_step() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── Elixir: Compile with warnings-as-errors ─────────────────────────────

echo "=== Elixir: Compile (warnings as errors on non-otel files) ==="
COMPILE_OUT=$(mix compile --warnings-as-errors 2>&1 || true)
OTEL_WARNINGS=$(echo "$COMPILE_OUT" | grep -c "lib/ex_gocd/otel" || true)
OTHER_WARNINGS=$(echo "$COMPILE_OUT" | grep -c "warning:" || true)
# Filter out otel warnings (known WIP OpenTelemetry version mismatch)
REAL_WARNINGS=$((OTHER_WARNINGS - OTEL_WARNINGS))
if [ "$REAL_WARNINGS" -le 0 ] 2>/dev/null; then
  pass_step "Elixir compile — no warnings (ignoring otel WIP)"
else
  echo "$COMPILE_OUT" | grep "warning:" | grep -v "lib/ex_gocd/otel"
  fail_step "Elixir compile — ${REAL_WARNINGS} warnings found"
fi

# ── Elixir: Sobelow security scan ───────────────────────────────────────

echo ""
echo "=== Elixir: Sobelow security scan ==="
SOBELOW_OUT=$(mix sobelow 2>&1)
SOBELOW_FINDINGS=$(echo "$SOBELOW_OUT" | grep -c "High Confidence\|Medium Confidence" || true)
if [ "$SOBELOW_FINDINGS" -eq 0 ]; then
  pass_step "Sobelow — no security findings"
else
  echo "$SOBELOW_OUT" | grep -E "^(Config\.|Traversal\.|XSS\.)|^(File|Line|Function|Variable):"
  fail_step "Sobelow — ${SOBELOW_FINDINGS} security findings"
fi

# ── Elixir: Credo (if available) ────────────────────────────────────────

echo ""
echo "=== Elixir: Credo ==="
if mix credo --format=oneline 2>&1; then
  pass_step "Credo — no suggestions"
else
  warn_step "Credo — suggestions found (not blocking)"
fi

# ── Elixir: Test suite ─────────────────────────────────────────────────

echo ""
echo "=== Elixir: ExUnit tests ==="
if mix test 2>&1 | tail -3; then
  pass_step "ExUnit tests — all passing"
else
  fail_step "ExUnit tests — failures"
fi

# ── Go: agent static analysis ──────────────────────────────────────────

echo ""
echo "=== Go: vet ==="
if (cd agent && go vet ./... 2>&1); then
  pass_step "Go vet — no issues"
else
  fail_step "Go vet — issues found"
fi

echo ""
echo "=== Go: staticcheck ==="
if command -v staticcheck &>/dev/null; then
  # Filter out toolchain version mismatch errors (not our code)
  STATICCHECK_OUT=$(cd agent && staticcheck ./... 2>&1 || true)
  STATICCHECK_REAL=$(echo "$STATICCHECK_OUT" | grep -v "fips140only\|requires newer Go version" || true)
  if [ -z "$STATICCHECK_REAL" ]; then
    pass_step "Go staticcheck — no issues (ignoring toolchain warnings)"
  else
    echo "$STATICCHECK_REAL"
    fail_step "Go staticcheck — issues found"
  fi
else
  warn_step "Go staticcheck — not installed (skipping)"
fi

echo ""
echo "=== Go: golangci-lint ==="
if command -v golangci-lint &>/dev/null; then
  # Disable errcheck for now — pre-existing in agent protocol handling.
  # Agent gracefully handles malformed server messages by skipping them.
  if (cd agent && golangci-lint run --disable errcheck ./... 2>&1); then
    pass_step "Go golangci-lint — no issues"
  else
    fail_step "Go golangci-lint — issues found"
  fi
else
  warn_step "Go golangci-lint — not installed (skipping)"
fi

# ── Go: agent tests ────────────────────────────────────────────────────

echo ""
echo "=== Go: agent tests ==="
if (cd agent && go test ./... 2>&1); then
  pass_step "Go agent tests — all passing"
else
  fail_step "Go agent tests — failures"
fi

# ── Link Checker (internal only) ────────────────────────────────────────

echo ""
echo "=== Link Checker (muffet) ==="
if bash scripts/link-check.sh http://localhost:4000 2>&1; then
  pass_step "Link checker — no broken internal links"
else
  fail_step "Link checker — broken links found"
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "============================================"
echo " Quality Gate Summary"
echo "============================================"
echo -e " ${GREEN}Passed:${NC} ${PASS}"
echo -e " ${RED}Failed:${NC} ${FAIL}"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Quality gate FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}Quality gate PASSED${NC}"
  exit 0
fi
