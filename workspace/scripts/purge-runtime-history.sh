#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

find agents -type f \( -name '*.jsonl' -o -name '*.jsonl.deleted.*' -o -name '*.lock' -o -name '*.bak*' \) -delete || true
find cron/runs -type f -name '*.jsonl' -delete 2>/dev/null || true
rm -rf workspace/memory/* workspace/.state/* workspace/tmp/* 2>/dev/null || true

echo "runtime-history-purged"
