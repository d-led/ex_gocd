#!/bin/bash
# Build all managed plugin Docker images locally.
# Phoenix-only — no variants needed.

set -euo pipefail
cd "$(dirname "$0")/.."

PLUGINS_DIR="plugins/managed"
PLUGINS=(corp_policy enterprise_hierarchy sample_scheduling_plugin simple_org_chart)

for plugin in "${PLUGINS[@]}"; do
  tag="ex_gocd-plugin-${plugin}:latest"
  echo "=== Building ${plugin} ==="
  docker build -t "${tag}" "${PLUGINS_DIR}/${plugin}"
  echo "  -> ${tag}"
done

echo ""
echo "=== All plugin images ==="
docker images --filter "reference=ex_gocd-plugin-*" --format "{{.Repository}}:{{.Tag}}  {{.Size}}"
