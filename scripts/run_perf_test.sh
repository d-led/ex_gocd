#!/bin/bash
# Copyright 2026 ex_gocd
# Local execution wrapper for E2E performance test in Docker.
set -e

# Change directory to the root of the project
cd "$(dirname "$0")/.."

echo "Stopping and cleaning up any existing test containers..."
docker compose -f docker-compose.test.yml down -v --remove-orphans

echo "Starting test environment..."
# Build and launch compose stack. Returns the exit code of the test-runner.
exit_code=0
docker compose -f docker-compose.test.yml up --build --abort-on-container-exit --exit-code-from test-runner || exit_code=$?

echo "Stopping environment and cleaning up volumes..."
docker compose -f docker-compose.test.yml down -v

if [ $exit_code -ne 0 ]; then
  echo "E2E Performance verification FAILED with exit code: $exit_code"
  exit $exit_code
else
  echo "E2E Performance verification PASSED!"
  exit 0
fi
