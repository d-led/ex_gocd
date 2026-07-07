#!/bin/bash
# Build all managed plugin Docker images locally.
# Usage: ./scripts/build-plugins.sh [git|full|both]
#   git  — build git variant only (default)
#   full — build full variant only
#   both — build both variants

set -euo pipefail
cd "$(dirname "$0")/.."

VARIANT="${1:-both}"
PLUGINS_DIR="plugins/managed"
PLUGINS=(corp_policy enterprise_hierarchy sample_scheduling_plugin simple_org_chart)

build_plugin() {
  local plugin="$1"
  local variant="$2"
  local tag="ex_gocd-plugin-${plugin}:${variant}"
  echo "=== Building ${plugin} (${variant}) ==="
  docker build --build-arg VARIANT="${variant}" -t "${tag}" "${PLUGINS_DIR}/${plugin}"
  echo "  -> ${tag}"
}

for plugin in "${PLUGINS[@]}"; do
  case "$VARIANT" in
    both)
      build_plugin "$plugin" git
      build_plugin "$plugin" full
      ;;
    git|full)
      build_plugin "$plugin" "$VARIANT"
      ;;
    *)
      echo "Unknown variant: $VARIANT (use: git, full, both)"
      exit 1
      ;;
  esac
done

echo ""
echo "=== All plugin images ==="
docker images --filter "reference=ex_gocd-plugin-*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
