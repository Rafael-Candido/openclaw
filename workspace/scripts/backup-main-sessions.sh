#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Backward-compatible wrapper. Backups are now a single daily artifact managed
# by openclaw-hygiene.sh instead of unbounded timestamped directories.
exec "${SCRIPT_DIR}/openclaw-hygiene.sh" --apply --backup-only "$@"
