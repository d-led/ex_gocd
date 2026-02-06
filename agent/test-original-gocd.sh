#!/bin/bash
# Test our agent against the original GoCD server

set -e

echo "Testing our Go agent against original GoCD server..."
echo ""
echo "Expected to fail because protocols are incompatible!"
echo ""

export GOCD_SERVER_URL="http://localhost:8153/go"
export GOCD_AUTO_REGISTER_KEY="123456789abcdef"
export GOCD_AUTO_REGISTER_RESOURCES="golang,modern"
export GOCD_AGENT_WORK_DIR="./work"

./bin/gocd-agent
