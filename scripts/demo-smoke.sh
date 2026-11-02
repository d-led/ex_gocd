#!/usr/bin/env bash
# Asks a running quickstart the questions a first-time visitor asks.
#
#   docker compose -f docker-compose.quickstart.yml up --build -d
#   scripts/demo-smoke.sh
#
# Exit code 0 means the demo is usable: the page renders, an agent is connected,
# pipelines exist, and the MCP endpoint answers as a client expects.
set -euo pipefail

BASE="${BASE:-http://localhost:4000}"
failures=0

check() {
  local what="$1" result="$2"
  if [ "$result" = "ok" ]; then
    printf '  ok    %s\n' "$what"
  else
    printf '  FAIL  %s — %s\n' "$what" "$result"
    failures=$((failures + 1))
  fi
}

rpc() {
  # rpc <json> — one JSON-RPC message, the response on stdout.
  curl -fsS "$BASE/mcp" -H 'content-type: application/json' -d "$1"
}

echo "demo at $BASE"

status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/go/api/v1/health" || true)
check "health endpoint answers 200" "$([ "$status" = "200" ] && echo ok || echo "HTTP $status")"

# A page that renders is not the same as a page with content: the session cookie
# is written on every HTML response, so a bad secret shows up here as a 500.
page=$(curl -s -o /tmp/demo-smoke.html -w '%{http_code}' "$BASE/" || true)
bytes=$(wc -c < /tmp/demo-smoke.html | tr -d ' ')
check "front page renders" "$([ "$page" = "200" ] && [ "$bytes" -gt 5000 ] && echo ok || echo "HTTP $page, $bytes bytes")"

version=$(rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"demo-smoke","version":"0"}}}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["protocolVersion"])' 2>/dev/null || true)
check "MCP initialize negotiates a version" "$([ -n "$version" ] && echo ok || echo 'no protocolVersion')"

tools=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["result"]["tools"]))' 2>/dev/null || echo 0)
check "MCP lists tools" "$([ "$tools" -gt 0 ] && echo ok || echo 'none listed')"

pipelines=$(rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"gocd_dashboard","arguments":{}}}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["content"][0]["text"].splitlines()[0])' 2>/dev/null || true)
check "the dashboard has pipelines ($pipelines)" "$([ -n "$pipelines" ] && echo ok || echo 'dashboard tool returned nothing')"

agents=$(rpc '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"gocd_list_agents","arguments":{}}}' \
  | python3 -c 'import json,sys; t=json.load(sys.stdin)["result"]["content"][0]["text"]; print(t)' 2>/dev/null || true)
check "an agent is registered" "$(echo "$agents" | grep -qi "idle\|building\|agent" && echo ok || echo 'no agents')"

if [ "$failures" -eq 0 ]; then
  echo "demo is usable — open $BASE"
else
  echo "$failures check(s) failed"
  exit 1
fi
