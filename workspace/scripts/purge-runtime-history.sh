#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Backward-compatible wrapper for callers that explicitly ask for a full
# runtime-history purge.
exec "${SCRIPT_DIR}/openclaw-hygiene.sh" --apply --purge-history "$@"
