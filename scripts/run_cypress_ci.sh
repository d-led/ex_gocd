#!/bin/bash
# CI Cypress runner — starts server with mock data, waits, runs tests.
# Assumes the Docker image is already built and tagged as ex_gocd:ci.
set -e

cd "$(dirname "$0")/.."

echo "=== Starting server with mock data ==="
docker rm -f ex_gocd_ci 2>/dev/null || true
docker run -d --name ex_gocd_ci --network host \
  -e DATABASE_URL="ecto://postgres:postgres@localhost/ex_gocd_dev" \
  -e SECRET_KEY_BASE="test-secret-key-base-for-ci-purpose-only" \
  -e USE_MOCK_DATA="true" \
  -e PORT=4000 \
  -e PHX_SERVER=true \
  ex_gocd:ci \
  sh -c "/app/bin/ex_gocd eval 'ExGoCD.Release.migrate' && /app/bin/ex_gocd start"

echo "=== Waiting for server ==="
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/materials 2>/dev/null | grep -q 200; then
    echo "Server ready on port 4000"
    break
  fi
  echo "  waiting... ($i/30)"
  sleep 2
done

echo "=== Running Cypress tests ==="
mkdir -p cypress/results
CYPRESS_BASE_URL=http://localhost:4000 npx cypress run --browser chrome || true

echo "=== Done ==="
