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

# Track statuses for summary reporting
SERVER_READY_STATUS="⏳ Pending"
GO_AGENT_STATUS="⏳ Pending"
JOB_STATUS="⏳ Pending"
OTP_AGENTS_STATUS="⏳ Pending"
MEM_STATUS="⏳ Pending"
JOB_RESULT="Pending"

# Track time for summary reporting
START_TIME=$SECONDS
t_start_step=$SECONDS
current_step="server_ready"

duration_server=0
duration_go_agent=0
duration_job=0
duration_sim_agents=0
duration_mem_check=0

# JUnit XML Generator Trap
generate_report() {
  local exit_code=$?
  local failures=0
  local error_tag=""
  
  # Calculate duration of the active step at time of exit/failure
  local elapsed=$((SECONDS - t_start_step))
  case "$current_step" in
    server_ready) duration_server=$elapsed ;;
    go_agent) duration_go_agent=$elapsed ;;
    job_exec) duration_job=$elapsed ;;
    sim_agents) duration_sim_agents=$elapsed ;;
    mem_check) duration_mem_check=$elapsed ;;
  esac

  local total_time=$((SECONDS - START_TIME))

  if [ $exit_code -ne 0 ]; then
    failures=1
    error_tag="<failure message=\"E2E Scalability or Performance Verification failed\" type=\"AssertionError\">Exit code: $exit_code</failure>"
    
    # If the step was running when it crashed/exited, update its status to Failed
    if [ "$SERVER_READY_STATUS" = "⏳ Pending" ]; then SERVER_READY_STATUS="❌ Failed"; fi
    if [ "$GO_AGENT_STATUS" = "⏳ Pending" ] && [ "$SERVER_READY_STATUS" = "✅ Passed" ]; then GO_AGENT_STATUS="❌ Failed"; fi
    if [ "$JOB_STATUS" = "⏳ Pending" ] && [ "$GO_AGENT_STATUS" = "✅ Passed" ]; then JOB_STATUS="❌ Failed"; JOB_RESULT="Failed"; fi
    if [ "$OTP_AGENTS_STATUS" = "⏳ Pending" ] && [ "$JOB_STATUS" = "✅ Passed" ]; then OTP_AGENTS_STATUS="❌ Failed"; fi
    if [ "$MEM_STATUS" = "⏳ Pending" ] && [ "$OTP_AGENTS_STATUS" = "✅ Passed" ]; then MEM_STATUS="❌ Failed"; fi
  fi

  cat <<EOF > /app/e2e-report.xml
<testsuites>
  <testsuite name="E2E Scalability and Performance" tests="5" failures="$failures" errors="0" time="$total_time">
    <testcase name="Server ready check" classname="E2E.Scalability" time="$duration_server">
      <system-out>Phoenix server successfully booted and responded to /api/stats.</system-out>
    </testcase>
    <testcase name="Go Agent registration" classname="E2E.Scalability" time="$duration_go_agent">
      <system-out>Go agent registered. Total agents online: ${TOTAL_AGENTS:-0}.</system-out>
    </testcase>
    <testcase name="E2E Job execution" classname="E2E.Scalability" time="$duration_job">
      <system-out>E2E Job execution finished with result: ${JOB_RESULT:-Unknown}.</system-out>
    </testcase>
    <testcase name="Simulated OTP Agents registration ($AGENT_COUNT agents)" classname="E2E.Scalability" time="$duration_sim_agents">
      <system-out>Simulated agents connected: ${ACTIVE_CONNS:-0} active connections out of $AGENT_COUNT expected.</system-out>
      $error_tag
    </testcase>
    <testcase name="Erlang VM memory check" classname="E2E.Scalability" time="$duration_mem_check">
      <system-out>Erlang VM memory consumption: ${MEM_MB:-0} MB (Limit: 1500 MB).</system-out>
    </testcase>
  </testsuite>
</testsuites>
EOF
  echo "Test results written to /app/e2e-report.xml"

  cat <<EOF > /app/perf-summary.md
### 🚀 E2E Scale & Performance Test Results

| Metric / Check | Target / Expected | Actual / Measured | Status | Duration |
| :--- | :--- | :--- | :---: | :---: |
| **Server Ready Check** | Server is responsive | UP | $SERVER_READY_STATUS | ${duration_server}s |
| **Go Agent Registration** | At least 1 registered | ${TOTAL_AGENTS:-0} total | $GO_AGENT_STATUS | ${duration_go_agent}s |
| **E2E Job Execution** | Job state: Completed, Result: Passed | Result: ${JOB_RESULT:-Unknown} | $JOB_STATUS | ${duration_job}s |
| **Simulated OTP Agents** | $AGENT_COUNT agents connected | ${ACTIVE_CONNS:-0} active | $OTP_AGENTS_STATUS | ${duration_sim_agents}s |
| **Erlang VM Memory** | Memory < 1500 MB | ${MEM_MB:-0} MB | $MEM_STATUS | ${duration_mem_check}s |

*Total Suite Execution Time: ${total_time}s*
*Exit Code: $exit_code*
EOF
  echo "Markdown performance summary written to /app/perf-summary.md"
}
trap generate_report EXIT

# 1. Wait for Phoenix server to be ready
echo "Waiting for Phoenix server at $SERVER_URL..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" "$SERVER_URL/api/stats" | grep -q "200"; then
    echo "Phoenix server is UP!"
    SERVER_READY_STATUS="✅ Passed"
    duration_server=$((SECONDS - t_start_step))
    current_step="go_agent"
    t_start_step=$SECONDS
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
    GO_AGENT_STATUS="✅ Passed"
    duration_go_agent=$((SECONDS - t_start_step))
    current_step="job_exec"
    t_start_step=$SECONDS
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
      JOB_STATUS="✅ Passed"
      JOB_RESULT="Passed"
      duration_job=$((SECONDS - t_start_step))
      current_step="sim_agents"
      t_start_step=$SECONDS
      break
    else
      echo "E2E Job execution failed with result: $RESULT"
      JOB_STATUS="❌ Failed"
      JOB_RESULT="Failed"
      duration_job=$((SECONDS - t_start_step))
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
OTP_AGENTS_STATUS="✅ Passed"
duration_sim_agents=$((SECONDS - t_start_step))
current_step="mem_check"
t_start_step=$SECONDS

# Convert memory to MB for print
MEM_MB=$((MEM_BYTES / 1024 / 1024))
echo "Erlang VM memory usage: ${MEM_MB}MB"

if [ "$MEM_MB" -gt 1500 ]; then
  echo "Assertion Failed: Erlang VM memory usage exceeds 1.5GB limit: ${MEM_MB}MB"
  exit 1
fi
MEM_STATUS="✅ Passed"
duration_mem_check=$((SECONDS - t_start_step))

echo "===================================================="
echo "ALL E2E AND PERFORMANCE ASSERTIONS PASSED SUCCESSFULLY!"
echo "===================================================="
exit 0
