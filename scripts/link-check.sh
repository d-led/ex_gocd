#!/usr/bin/env bash
# Link checker quality gate — checks only localhost internal links.
# Uses lychee (Rust-based, fast, low memory).
# Skips external links.
set -euo pipefail

BASE_URL="${1:-http://localhost:4000}"
LYCHEE="$(which lychee 2>/dev/null || echo '')"

if [ -z "$LYCHEE" ]; then
  echo "[SKIP] lychee not installed (run: brew install lychee)"
  exit 0
fi

# Check if the server is actually reachable
if ! curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w "%{http_code}" "$BASE_URL" | grep -qE '^(2|3)'; then
  echo "[SKIP] Link checker — server not reachable at $BASE_URL (is it running?)"
  exit 0
fi

echo "=== Link Checker (lychee) ==="

# lychee: check localhost links, follow links to pipeline/stage/job detail pages.
# Multiple entry points ensure deep pages (pipelines, agents, admin) are crawled.
"$LYCHEE" \
  --max-concurrency 2 \
  --max-redirects 5 \
  --timeout 10 \
  --accept 200,301,302,304 \
  --exclude 'https://github\.com/.*' \
  --exclude 'https://www\.mozilla\.org/.*' \
  --exclude 'mailto:' \
  --exclude '/assets/app\.css' \
  --exclude '/favicon.*\.png' \
  --exclude '^#' \
  --no-progress \
  "$BASE_URL" \
  "$BASE_URL/pipelines" \
  "$BASE_URL/agents" \
  "$BASE_URL/admin" \
  "$BASE_URL/analytics" \
  "$BASE_URL/materials" \
  2>&1

if [ $? -eq 0 ]; then
  echo "[PASS] Link checker — no broken internal links"
else
  echo "[FAIL] Link checker — broken links found"
  exit 1
fi
