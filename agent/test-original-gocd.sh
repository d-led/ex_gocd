#!/bin/bash
# Acceptance test: our Go agent against a real (official) GoCD server.
#
# This is the test that decides whether the Go agent is a drop-in replacement
# for the official Java agent. It currently FAILS, and that is the correct
# result: the agent still speaks a WebSocket protocol that GoCD removed in
# 19.6.0 (commit d45efb4d25 "Remove build session and agent websocket").
#
# The official agent uses HTTP remoting instead. The exact contract to
# implement is captured in test/fixtures/remoting/ — see that directory's
# README for how the captures were made and what each endpoint must return.
#
# Prerequisites:
#   cd ../../gocd_docker_compose_example/static_config && docker compose up -d
#   (starts gocd/gocd-server:v25.4.0 on http://localhost:8153/go)
#
# Usage: ./test-original-gocd.sh
# Exit code: 0 when the agent registers with the official server, 1 otherwise.

set -uo pipefail

SERVER_URL="${GOCD_SERVER_URL:-http://localhost:8153/go}"
AUTO_REGISTER_KEY="${GOCD_AUTO_REGISTER_KEY:-123456789abcdef}"
AGENT_TIMEOUT_SECONDS="${AGENT_TIMEOUT_SECONDS:-60}"

echo "Checking the official GoCD server at ${SERVER_URL} ..."
if ! curl -sf -o /dev/null "${SERVER_URL}/api/v1/health"; then
  echo "FAIL: no GoCD server at ${SERVER_URL}."
  echo "      Start one with: (cd ../../gocd_docker_compose_example/static_config && docker compose up -d)"
  exit 1
fi

echo "Building the agent ..."
if ! go build -o bin/gocd-agent .; then
  echo "FAIL: the agent does not build."
  exit 1
fi

echo "Running the agent against the official server for ${AGENT_TIMEOUT_SECONDS}s ..."

agent_log="$(mktemp)"
./bin/gocd-agent \
  --server-url "${SERVER_URL}" \
  --work-dir ./work-acceptance \
  --auto-register-key "${AUTO_REGISTER_KEY}" \
  --auto-register-resources "golang,modern" \
  >"${agent_log}" 2>&1 &
agent_pid=$!

# Poll the server for an agent that registered with the resource we asked for.
registered=""
deadline=$((SECONDS + AGENT_TIMEOUT_SECONDS))
while [ "${SECONDS}" -lt "${deadline}" ]; do
  registered="$(curl -s -H 'Accept: application/vnd.go.cd+json' "${SERVER_URL}/api/agents" \
    | grep -o '"resources":\[[^]]*"golang"' | head -1)"
  [ -n "${registered}" ] && break
  sleep 3
done

kill "${agent_pid}" 2>/dev/null
wait "${agent_pid}" 2>/dev/null

if [ -n "${registered}" ]; then
  echo "PASS: the agent registered with the official GoCD server."
  rm -f "${agent_log}"
  exit 0
fi

echo "FAIL: the agent never registered with the official GoCD server."
echo
echo "Cause: the agent talks WebSocket at /agent-websocket, which GoCD removed in"
echo "       19.6.0. The official server only accepts HTTP POST to /go/remoting/api/agent/*."
echo "Fix:   implement the HTTP remoting client, using test/fixtures/remoting/ as the spec."
echo
echo "Last agent output:"
tail -20 "${agent_log}"
rm -f "${agent_log}"
exit 1
