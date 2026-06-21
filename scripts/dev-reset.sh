#!/usr/bin/env bash
# ── Dev Reset ──────────────────────────────────────────────────────────
# Resets the ex_gocd development database and re-seeds with demo data.
# Useful when pipeline state gets stuck or after schema changes.
#
# Usage:
#   ./scripts/dev-reset.sh          # reset DB only
#   ./scripts/dev-reset.sh --full   # reset DB + recompile + restart hint
set -euo pipefail

cd "$(dirname "$0")/.."

FULL="${1:-}"

echo "=== Dropping and recreating dev database ==="
MIX_ENV=dev mix ecto.drop --force 2>/dev/null || true
MIX_ENV=dev mix ecto.create 2>/dev/null
MIX_ENV=dev mix ecto.migrate

echo ""
echo "=== Seeding demo data ==="
MIX_ENV=dev mix run priv/repo/seeds.exs 2>/dev/null || echo "(seed script optional - continuing)"

echo ""
echo "=== Dev reset complete ==="
echo ""
echo "Database reset. Scheduler will reload pending jobs automatically."
if [[ "$FULL" == "--full" ]]; then
  echo ""
  echo "To restart the server:"
  echo "  mix phx.server"
  echo ""
  echo "To start an agent:"
  echo "  ./scripts/start-agent.sh"
fi
