#!/bin/bash
# Test mock mode

echo "Testing mock mode with USE_MOCK_DATA=true..."

cd /Users/dmitryledentsov/src/gocd-rewrite/ex_gocd

# Start server in mock mode in background
USE_MOCK_DATA=true elixir --sname mock_test -S mix phx.server > /tmp/mock_server.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting for server to start..."

# Wait for server to be ready
sleep 5

# Test the API
echo ""
echo "Testing /api/agents endpoint..."
curl -s 'http://localhost:4000/api/agents' | \
  python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    agents = data['_embedded']['agents']
    print(f'Total agents in mock mode: {len(agents)}')
    print('')
    for agent in agents:
        hostname = agent['hostname']
        state = agent['agent_state']
        config = agent['agent_config_state']
        resources = len(agent.get('resources', []))
        print(f'  - {hostname}: {state} ({config}) - {resources} resources')
except Exception as e:
    print(f'Error: {e}')
"

echo ""
echo "Killing server (PID: $SERVER_PID)..."
kill $SERVER_PID 2>/dev/null

echo "Done!"
