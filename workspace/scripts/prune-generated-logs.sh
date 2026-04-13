#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Backward-compatible wrapper. The old positional retention-days argument is
# accepted but the canonical policy now lives in openclaw-hygiene.sh.
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
  export OPENCLAW_GENERATED_RETENTION_DAYS="$1"
  shift || true
fi

exec "${SCRIPT_DIR}/openclaw-hygiene.sh" --apply --generated-only "$@"
