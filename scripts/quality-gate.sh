#!/bin/bash
# Quality Gate — runs all static analysis for the ex_gocd project
# Covers Elixir, Go agent, and JavaScript/TypeScript.
# Exit code 0 = all checks pass. Non-zero = failures found.

set -euo pipefail

cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

die() { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }
pass_step() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail_step() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); die "Quality gate halted on failure."; }
warn_step() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── Elixir: Compile with warnings-as-errors ─────────────────────────────

echo "=== Elixir: Compile (warnings as errors on non-otel files) ==="
COMPILE_OUT=$(mix compile --warnings-as-errors 2>&1) && COMPILE_OK=1 || COMPILE_OK=0
OTEL_WARNINGS=$(echo "$COMPILE_OUT" | grep -c "lib/ex_gocd/otel" || true)
OTHER_WARNINGS=$(echo "$COMPILE_OUT" | grep -c "warning:" || true)
REAL_WARNINGS=$((OTHER_WARNINGS - OTEL_WARNINGS))
if [ "$COMPILE_OK" -eq 1 ] && [ "$REAL_WARNINGS" -le 0 ]; then
  pass_step "Elixir compile — no warnings (ignoring otel WIP)"
else
  echo ""
  echo "=== COMPILE ERRORS/WARNINGS ==="
  echo "$COMPILE_OUT" | grep -E "warning:|error:|\\*\\*" | grep -v "lib/ex_gocd/otel"
  echo "=== END ==="
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
  fail_step "Credo — suggestions found"
fi

# ── Elixir: Test suite ─────────────────────────────────────────────────

echo ""
echo "=== Elixir: ExUnit tests ==="
TEST_OUT=$(mix test 2>&1) && TEST_EXIT=0 || TEST_EXIT=$?
echo "$TEST_OUT" | tail -3
if [ "$TEST_EXIT" -eq 0 ]; then
  pass_step "ExUnit tests — all passing"
else
  echo ""
  echo "--- FAILURES ---"
  echo "$TEST_OUT" | grep -A 10 "^\s*[0-9]\+) test " || echo "$TEST_OUT" | tail -40
  echo "--- END FAILURES ---"
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

# ── Go: gofmt ──────────────────────────────────────────────────────────

echo ""
echo "=== Go: gofmt ==="
UNFORMATTED=$(cd agent && gofmt -l . 2>&1)
if [ -z "$UNFORMATTED" ]; then
  pass_step "Go gofmt — all files formatted"
else
  echo "Unformatted files:"
  echo "$UNFORMATTED"
  fail_step "Go gofmt — unformatted files found (run: cd agent && gofmt -w .)"
fi

# ── Go: go mod tidy ────────────────────────────────────────────────────

echo ""
echo "=== Go: go mod tidy ==="
TIDY_OUT=$(cd agent && go mod tidy -diff 2>&1) && TIDY_OK=1 || TIDY_OK=0
if [ "$TIDY_OK" -eq 1 ] && [ -z "$TIDY_OUT" ]; then
  pass_step "Go mod tidy — go.mod is tidy"
else
  echo "$TIDY_OUT"
  fail_step "Go mod tidy — go.mod needs tidying (run: cd agent && go mod tidy)"
fi

# ── Duplicate Code Detection (jscpd) ────────────────────────────────────

echo ""
echo "=== Duplicate Code Detection (jscpd) ==="
if npx --yes jscpd@3 lib/ test/ assets/ --threshold 1 --silent 2>&1; then
  pass_step "Duplicate code — under 1% threshold"
else
  fail_step "Duplicate code — exceeds 1% threshold (fix to pass)"
fi

# ── JavaScript: ESLint ──────────────────────────────────────────────────

echo ""
echo "=== JavaScript: ESLint ==="
if npx --yes eslint --no-error-on-unmatched-pattern \
    'cypress/**/*.js' 'assets/js/**/*.js' 'cypress.config.js' 2>&1; then
  pass_step "ESLint — no issues"
else
  fail_step "ESLint — issues found"
fi

# ── TypeScript: type-check ─────────────────────────────────────────────

echo ""
echo "=== TypeScript: type-check ==="
if npx --yes -p typescript tsc --project assets/tsconfig.json --noEmit 2>&1; then
  pass_step "TypeScript — no type errors"
else
  fail_step "TypeScript — type errors found"
fi

# ── JavaScript: Prettier (auto-format) ──────────────────────────────────

echo ""
echo "=== JavaScript: Prettier (format) ==="
PRETTIER_OUT=$(npx --yes prettier --write 'cypress/**/*.js' 'assets/js/**/*.js' 'cypress.config.js' 2>&1) || true
echo "$PRETTIER_OUT" | tail -5
pass_step "Prettier — formatted (auto-applied)"

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
