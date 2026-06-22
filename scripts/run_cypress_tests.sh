#!/bin/bash
# Copyright 2026 ex_gocd
# Automated script to run Cypress tests in mock mode.

set -e

# Change directory to the root of the project
cd "$(dirname "$0")/.."

echo "Starting Elixir Phoenix server on port 4001 with USE_MOCK_DATA=true..."

# Ensure migrations are up to date (Phoenix checks this on startup)
MIX_ENV=test mix ecto.migrate --quiet 2>/dev/null || true

PORT=4001 USE_MOCK_DATA=true elixir --sname mock_test -S mix phx.server > /tmp/mock_server_cypress.log 2>&1 &
SERVER_PID=$!

# Ensure the server is killed if the script is interrupted or finishes
cleanup() {
  echo ""
  echo "Cleaning up..."
  if [ -n "$SERVER_PID" ]; then
    echo "Stopping mock server (PID: $SERVER_PID)..."
    kill $SERVER_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Waiting for mock server to start on port 4001..."
READY=false
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:4001/materials" | grep -q "200"; then
    echo "Mock server is UP and ready on port 4001!"
    READY=true
    break
  fi
  echo "Server not ready yet, retrying in 1s... ($i/30)"
  sleep 1
done

if [ "$READY" = false ]; then
  echo "Error: Phoenix server failed to start on port 4001 in time."
  echo "Logs from /tmp/mock_server_cypress.log:"
  cat /tmp/mock_server_cypress.log | tail -n 30
  exit 1
fi

echo "===================================================="
echo "Running Cypress E2E tests against http://localhost:4001..."
echo "===================================================="

# Run Cypress with the base URL override and select spec list (excluding agent daemon E2E specs)
exit_code=0
# Cypress specPattern + excludeSpecPattern are configured in cypress.config.js.
# No --spec override needed — Cypress picks up all non-excluded specs.

CYPRESS_BASE_URL=http://localhost:4001 npm run cypress:run || exit_code=$?


if [ $exit_code -ne 0 ]; then
  echo "Cypress E2E tests FAILED!"
else
  echo "Cypress E2E tests PASSED successfully!"
fi

exit $exit_code
