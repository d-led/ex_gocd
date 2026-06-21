#!/usr/bin/env bash
set -euo pipefail

# Convert GoCD SCSS to CSS (entry-point mode). Idempotent: safe to run on each GoCD update.
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

# Show diff so you can see what changed (idempotent run → diff after each GoCD update)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ABS_OUTPUT="$(cd "$CONVERTER_DIR" && cd "$OUTPUT_DIR" && pwd)"
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo ""
  echo "--- Git diff of converted CSS ---"
  git -C "$REPO_ROOT" diff --no-ext-diff -- "$ABS_OUTPUT" || true
fi
