#!/bin/bash
# Acceptance test: our Go agent against a real (official) GoCD server.
#
# Decides whether the agent is a drop-in replacement for the official Java
# agent. The agent speaks GoCD's HTTP remoting protocol (the WebSocket transport
# was removed from GoCD in 19.6.0, commit d45efb4d25).
#
# The wire contract is captured in test/fixtures/remoting/ — see that
# directory's README for the capture procedure.
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
AGENT_SERVER_URL="${SERVER_URL}" \
AGENT_WORK_DIR="./work-acceptance" \
AGENT_AUTO_REGISTER_KEY="${AUTO_REGISTER_KEY}" \
AGENT_AUTO_REGISTER_RESOURCES="golang,modern" \
  ./bin/gocd-agent >"${agent_log}" 2>&1 &
agent_pid=$!

# Poll the server for an agent that registered with the resource we asked for.
# The work dir is unique to this run, so matching on `sandbox` pins the result
# to the agent we just started (not a stale one from an earlier run).
registered=""
deadline=$((SECONDS + AGENT_TIMEOUT_SECONDS))
while [ "${SECONDS}" -lt "${deadline}" ]; do
  registered="$(curl -s -H 'Accept: application/vnd.go.cd+json' "${SERVER_URL}/api/agents" \
    | python3 -c 'import json,sys
d = json.load(sys.stdin)
agents = d.get("_embedded", {}).get("agents", [])
print(any(a.get("sandbox") == "work-acceptance/agent" and "golang" in (a.get("resources") or []) for a in agents))')"
  [ "${registered}" = "True" ] && break
  sleep 3
done

kill "${agent_pid}" 2>/dev/null
wait "${agent_pid}" 2>/dev/null

if [ "${registered}" = "True" ]; then
  echo "PASS: the agent registered with the official GoCD server."
  rm -f "${agent_log}"
  exit 0
fi

echo "FAIL: the agent never registered with the official GoCD server."
echo
echo "Cause: the agent did not register with the requested resources."
echo "       Check the agent log below for registration or remoting errors."
echo
echo "Last agent output:"
tail -20 "${agent_log}"
rm -f "${agent_log}"
exit 1
