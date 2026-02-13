#!/usr/bin/env bash
set -euo pipefail

# Directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERTER_DIR="$SCRIPT_DIR/../tools/converter"


# Default input: GoCD original SCSS directory
DEFAULT_INPUT="$SCRIPT_DIR/../../gocd/server/src/main/webapp/WEB-INF/rails/app/assets/new_stylesheets"
# Default output: assets/css/gocd
DEFAULT_OUTPUT="$SCRIPT_DIR/../assets/css/gocd"

INPUT_DIR="${1:-$DEFAULT_INPUT}"
OUTPUT_DIR="${2:-$DEFAULT_OUTPUT}"

cd "$CONVERTER_DIR"

if [ ! -d node_modules ]; then
  echo "Installing Node dependencies in $CONVERTER_DIR..."
  npm install
fi

# Ensure NODE_PATH includes node_modules for module resolution
export NODE_PATH="$CONVERTER_DIR/node_modules"

# Convert by entry points (avoids frameworks.scss and Rails-only deps); pass extra args to add more entries
ENTRIES=(
  "single_page_apps/new_dashboard.scss"
  "single_page_apps/agents.scss"
)
echo "Converting SCSS entry points from $INPUT_DIR → $OUTPUT_DIR"
node "$CONVERTER_DIR/css-convert.js" "$INPUT_DIR" "$OUTPUT_DIR" "${ENTRIES[@]}"
