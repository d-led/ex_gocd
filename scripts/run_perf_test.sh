#!/bin/bash
# Copyright 2026 ex_gocd
# Local execution wrapper for E2E performance test in Docker.
# Usage:
#   ./scripts/run_perf_test.sh          # uses pre-built images (CI default)
#   ./scripts/run_perf_test.sh --build  # builds images locally first
set -e

export COMPOSE_PROJECT_NAME=ex_gocd_test

cd "$(dirname "$0")/.."


echo "Stopping and cleaning up any existing test containers..."
docker compose -f docker-compose.test.yml down -v --remove-orphans

if [ "$1" = "--build" ]; then
  echo "Building server image locally..."
  docker build -t ex_gocd-web:local .
  echo "Building agent image locally..."
  docker build -t ex_gocd-agent:local agent/
  export SERVER_IMAGE=ex_gocd-web:local
  export AGENT_IMAGE=ex_gocd-agent:local
fi

echo "Starting test environment..."
echo "  SERVER_IMAGE=${SERVER_IMAGE:-ghcr.io/d-led/ex_gocd:latest}"
echo "  AGENT_IMAGE=${AGENT_IMAGE:-ghcr.io/d-led/ex_gocd-agent:latest}"

# Launch compose stack. Returns the exit code of the test-runner.
exit_code=0
docker compose -f docker-compose.test.yml up --abort-on-container-exit --exit-code-from test-runner || exit_code=$?

echo "Stopping environment and cleaning up volumes..."
docker compose -f docker-compose.test.yml down -v

if [ $exit_code -ne 0 ]; then
  echo "E2E Performance verification FAILED with exit code: $exit_code"
  exit $exit_code
else
  echo "E2E Performance verification PASSED!"
  exit 0
fi
