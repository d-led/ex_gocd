#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCREENSHOTS_DIR="$PROJECT_DIR/docs/screenshots"

echo "=== ex_gocd Screenshot Updater ==="

# Check app is reachable
if curl -s --connect-timeout 3 http://localhost:4000 > /dev/null 2>&1; then
  echo "✔ App reachable at http://localhost:4000"
else
  echo "⚠ App NOT reachable at http://localhost:4000 — screenshots may skip or fail"
fi

# Clean old screenshots
rm -rf "$SCREENSHOTS_DIR"/*.png 2>/dev/null || true
mkdir -p "$SCREENSHOTS_DIR"

# Install deps if needed
cd "$PROJECT_DIR"
if [ ! -d "node_modules" ]; then
  echo "Installing npm dependencies..."
  npm install
fi

echo "Running screenshot spec..."
npx cypress run --browser chrome --spec cypress/e2e/screenshot.cy.js || true

echo ""
echo "=== Captured screenshots ==="
if ls "$SCREENSHOTS_DIR"/*.png >/dev/null 2>&1; then
  for f in "$SCREENSHOTS_DIR"/*.png; do
    echo "  📸 $(basename "$f")"
  done
else
  echo "  (none)"
fi

echo ""
echo "Done. Screenshots in docs/screenshots/"
