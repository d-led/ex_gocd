#!/bin/bash
# Copyright 2026 ex_gocd
# E2E and performance verification orchestrator script.
set -e

echo "===================================================="
echo "Starting E2E Performance verification runner..."
echo "===================================================="

# Configurable agent count
AGENT_COUNT="${AGENT_COUNT:-100}"
EXPECTED_AGENTS=$((AGENT_COUNT + 1))

# JUnit XML Generator Trap
generate_report() {
  local exit_code=$?
  local failures=0
  local error_tag=""
  if [ $exit_code -ne 0 ]; then
    failures=1
    error_tag="<failure message=\"E2E Scalability or Performance Verification failed\" type=\"AssertionError\">Exit code: $exit_code</failure>"
  fi

  cat <<EOF > /app/e2e-report.xml
<testsuites>
  <testsuite name="E2E Scalability and Performance" tests="5" failures="$failures" errors="0">
    <testcase name="Server ready check" classname="E2E.Scalability" />
    <testcase name="Go Agent registration" classname="E2E.Scalability" />
    <testcase name="E2E Job execution" classname="E2E.Scalability" />
    <testcase name="Simulated OTP Agents registration ($AGENT_COUNT agents)" classname="E2E.Scalability">
      $error_tag
    </testcase>
    <testcase name="Erlang VM memory check" classname="E2E.Scalability" />
  </testsuite>
</testsuites>
EOF
  echo "Test results written to /app/e2e-report.xml"
}
trap generate_report EXIT

# 1. Wait for Phoenix server to be ready
echo "Waiting for Phoenix server at $SERVER_URL..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" "$SERVER_URL/api/stats" | grep -q "200"; then
    echo "Phoenix server is UP!"
    break
  fi
  echo "Server not ready, retrying in 1s... ($i/30)"
  sleep 1
done

# Check if server didn't boot
if ! curl -s -o /dev/null -w "%{http_code}" "$SERVER_URL/api/stats" | grep -q "200"; then
  echo "Error: Phoenix server failed to start."
  exit 1
fi

# 2. Wait for Go Agent to register and ping
echo "Waiting for Go Agent to auto-register and ping as Idle..."
for i in {1..30}; do
  STATS=$(curl -s "$SERVER_URL/api/stats")
  TOTAL_AGENTS=$(echo "$STATS" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
  IDLE_AGENTS=$(echo "$STATS" | grep -o '"idle":[0-9]*' | head -1 | cut -d: -f2)
  echo "Total agents: $TOTAL_AGENTS, Idle: $IDLE_AGENTS"
  if [ "$TOTAL_AGENTS" -ge 1 ] && [ "$IDLE_AGENTS" -ge 1 ]; then
    echo "Go Agent registered successfully!"
    break
  fi
  sleep 1
done

if [ "$TOTAL_AGENTS" -lt 1 ]; then
  echo "Error: Go Agent failed to register."
  exit 1
fi

# 3. Schedule E2E Pipeline Job matching the Go agent resource 'go'
echo "Scheduling E2E Pipeline Job..."
SCHEDULE_RES=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"pipeline": "e2e-pipeline", "stage": "build-stage", "job": "build-job", "resources": ["go"], "environments": ["test"]}' \
  "$SERVER_URL/api/jobs/schedule")
echo "Schedule response: $SCHEDULE_RES"

# 4. Wait for Job Execution to complete successfully
echo "Monitoring E2E Job execution..."
JOB_SUCCESS=false
for i in {1..60}; do
  STATE=$(psql "$DATABASE_URL" -t -A -c "SELECT state FROM agent_job_runs WHERE pipeline_name='e2e-pipeline' ORDER BY inserted_at DESC LIMIT 1;")
  RESULT=$(psql "$DATABASE_URL" -t -A -c "SELECT result FROM agent_job_runs WHERE pipeline_name='e2e-pipeline' ORDER BY inserted_at DESC LIMIT 1;")
  echo "Job State: $STATE, Result: $RESULT"
  if [ "$STATE" = "Completed" ]; then
    if [ "$RESULT" = "Passed" ]; then
      echo "E2E Job execution succeeded!"
      JOB_SUCCESS=true
      break
    else
      echo "E2E Job execution failed with result: $RESULT"
      exit 1
    fi
  fi
  sleep 1
done

if [ "$JOB_SUCCESS" = false ]; then
  echo "Error: E2E Job timed out."
  exit 1
fi

# Print console log from DB to verify console log uploading worked
echo "===================================================="
echo "Go Agent console output logs:"
echo "===================================================="
psql "$DATABASE_URL" -c "SELECT console_log FROM agent_job_runs WHERE pipeline_name='e2e-pipeline' ORDER BY inserted_at DESC LIMIT 1;"
echo "===================================================="

# 5. Start simulated OTP agents in the Erlang VM
echo "Triggering spawn of $AGENT_COUNT Elixir OTP simulated agents..."
SPAWN_RES=$(curl -s -X POST "$SERVER_URL/api/test/start_agents?count=$AGENT_COUNT")
echo "Spawn response: $SPAWN_RES"

# 6. Verify stats and assert on scale/performance
echo "Waiting for agents to establish connections and heartbeats..."
sleep 5

STATS=$(curl -s "$SERVER_URL/api/stats")
echo "Final Server Statistics:"
echo "$STATS"

TOTAL_AGENTS=$(echo "$STATS" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
ACTIVE_CONNS=$(echo "$STATS" | grep -o '"active_connections":[0-9]*' | head -1 | cut -d: -f2)
MEM_BYTES=$(echo "$STATS" | grep -o '"memory_total_bytes":[0-9]*' | head -1 | cut -d: -f2)

# Verify registry via /api/agents API
echo "Checking agent list via /api/agents API..."
API_AGENTS_COUNT=$(curl -s "$SERVER_URL/api/agents" | jq '._embedded.agents | length')
echo "API reports $API_AGENTS_COUNT total registered agents."

# Assertions
echo "Verifying E2E scale assertions..."
if [ "$TOTAL_AGENTS" -lt "$EXPECTED_AGENTS" ]; then
  echo "Assertion Failed: Expected at least $EXPECTED_AGENTS agents registered in stats, got: $TOTAL_AGENTS"
  exit 1
fi

if [ "$API_AGENTS_COUNT" -lt "$EXPECTED_AGENTS" ]; then
  echo "Assertion Failed: Expected at least $EXPECTED_AGENTS agents registered in agents API, got: $API_AGENTS_COUNT"
  exit 1
fi

if [ "$ACTIVE_CONNS" -lt "$AGENT_COUNT" ]; then
  echo "Assertion Failed: Expected at least $AGENT_COUNT active OTP connections, got: $ACTIVE_CONNS"
  exit 1
fi

# Convert memory to MB for print
MEM_MB=$((MEM_BYTES / 1024 / 1024))
echo "Erlang VM memory usage: ${MEM_MB}MB"

if [ "$MEM_MB" -gt 1500 ]; then
  echo "Assertion Failed: Erlang VM memory usage exceeds 1.5GB limit: ${MEM_MB}MB"
  exit 1
fi

echo "===================================================="
echo "ALL E2E AND PERFORMANCE ASSERTIONS PASSED SUCCESSFULLY!"
echo "===================================================="
exit 0
