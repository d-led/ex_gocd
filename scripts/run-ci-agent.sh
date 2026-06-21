#!/usr/bin/env bash
# Delegates to start-agent.sh — CI mode auto-detected via filename.
exec "$(dirname "$0")/start-agent.sh" "$@"
