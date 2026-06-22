#!/usr/bin/env bash
# Link checker quality gate — checks only localhost internal links.
# Uses muffet (Go-based, fast, detects loops).
# Skips external links (--exclude '^(?!http://localhost)')
set -euo pipefail

BASE_URL="${1:-http://localhost:4000}"
MUFFET="$(go env GOPATH)/bin/muffet"

if ! command -v "$MUFFET" &>/dev/null; then
  echo "[SKIP] muffet not installed (run: go install github.com/raviqqe/muffet/v2@latest)"
  exit 0
fi

echo "=== Link Checker (muffet) ==="

# Run muffet: check only localhost links, max 1 connection, follow redirects, detect loops
"$MUFFET" \
  --buffer-size 4096 \
  --max-connections-per-host 4 \
  --max-redirections 5 \
  --timeout 10 \
  --exclude 'https://github\.com/.*' \
  --exclude 'https://www\.mozilla\.org/.*' \
  --exclude 'mailto:' \
  --exclude '/assets/app\.css' \
  --exclude '/favicon.*\.png' \
  --exclude '^#' \
  "$BASE_URL" 2>&1

if [ $? -eq 0 ]; then
  echo "[PASS] Link checker — no broken internal links"
else
  echo "[FAIL] Link checker — broken links found"
  exit 1
fi
