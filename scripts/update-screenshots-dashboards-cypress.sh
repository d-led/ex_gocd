#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCREENSHOTS_DIR="$PROJECT_DIR/docs/screenshots"

echo "=== ex_gocd Dashboards Screenshot Updater ==="

# Check Jaeger
if curl -s --connect-timeout 3 http://localhost:16686/ > /dev/null 2>&1; then
  echo "✔ Jaeger reachable at http://localhost:16686"
else
  echo "⚠ Jaeger NOT reachable — jaeger screenshots will skip"
fi

# Check Grafana
if curl -s --connect-timeout 3 http://localhost:3000/ > /dev/null 2>&1; then
  echo "✔ Grafana reachable at http://localhost:3000"
else
  echo "⚠ Grafana NOT reachable — grafana screenshots will skip"
fi

# Clean old dashboard screenshots
rm -f "$SCREENSHOTS_DIR"/jaeger-*.png "$SCREENSHOTS_DIR"/grafana-*.png 2>/dev/null || true
mkdir -p "$SCREENSHOTS_DIR"

# Install deps if needed
cd "$PROJECT_DIR"
if [ ! -d "node_modules" ]; then
  echo "Installing npm dependencies..."
  npm install
fi

echo "Running dashboard screenshot spec..."
CYPRESS_baseUrl=http://localhost:3000 npx cypress run --browser chrome --spec cypress/e2e/screenshot-dashboards.cy.js || true

echo ""
echo "=== Captured dashboard screenshots ==="
if ls "$SCREENSHOTS_DIR"/jaeger-*.png "$SCREENSHOTS_DIR"/grafana-*.png >/dev/null 2>&1; then
  for f in "$SCREENSHOTS_DIR"/jaeger-*.png "$SCREENSHOTS_DIR"/grafana-*.png; do
    [ -f "$f" ] && echo "  📸 $(basename "$f")"
  done
else
  echo "  (none)"
fi

echo ""
echo "Done. Dashboard screenshots in docs/screenshots/"
