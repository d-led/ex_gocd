#!/bin/bash
# CI Cypress runner — starts server with mock data, waits, runs tests.
# Assumes the Docker image is already built and tagged as ex_gocd:ci.
set -e

cd "$(dirname "$0")/.."

# Generate a proper secret key base (Plug ≥1.19 requires ≥64 bytes)
SECRET_KEY_BASE=$(openssl rand -base64 64)
echo "=== Starting server with mock data ==="
docker rm -f ex_gocd_ci 2>/dev/null || true
docker run -d --name ex_gocd_ci --network host \
  -e DATABASE_URL="ecto://postgres:postgres@localhost/ex_gocd_dev" \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e USE_MOCK_DATA="true" \
  -e PORT=4000 \
  -e PHX_SERVER=true \
  ex_gocd:ci \
  sh -c "/app/bin/ex_gocd eval 'ExGoCD.Release.migrate' && /app/bin/ex_gocd start"

echo "=== Waiting for server ==="
server_ready=false
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/materials 2>/dev/null | grep -q 200; then
    echo "Server ready on port 4000"
    server_ready=true
    break
  fi
  echo "  waiting... ($i/30)"
  sleep 2
done

if [ "$server_ready" = false ]; then
  echo "=== ERROR: Server failed to start within 60 seconds ==="
  echo "=== Docker logs ==="
  docker logs ex_gocd_ci || true
  echo "=== Exiting with failure ==="
  exit 1
fi

echo "=== Running Cypress tests ==="
mkdir -p cypress/results
CYPRESS_BASE_URL=http://localhost:4000 npx cypress run --browser chrome || true

echo "=== Done ==="
