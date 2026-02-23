#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNS_DIR="${ROOT_DIR}/../cron/runs"
if [[ ! -d "${RUNS_DIR}" ]]; then
  RUNS_DIR="${HOME}/.openclaw/cron/runs"
fi

if [[ ! -d "${RUNS_DIR}" ]]; then
  echo '{"ok":false,"error":"runs_dir_not_found"}'
  exit 2
fi

python3 - "${RUNS_DIR}" <<'PY'
import datetime as dt
import json
import pathlib
import sys
from collections import defaultdict

runs_dir = pathlib.Path(sys.argv[1])
cut = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=24)).timestamp() * 1000

total_runs = 0
total_tokens = 0
by_job = defaultdict(lambda: {"runs": 0, "tokens": 0})

for f in runs_dir.glob("*.jsonl"):
    job_id = f.stem
    try:
        lines = f.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        continue
    for ln in lines:
        ln = ln.strip()
        if not ln:
            continue
        try:
            it = json.loads(ln)
        except Exception:
            continue
        ts = int(it.get("ts") or 0)
        if ts < cut:
            continue
        usage = it.get("usage") or {}
        tokens = int(usage.get("total_tokens") or 0)
        total_runs += 1
        total_tokens += tokens
        by_job[job_id]["runs"] += 1
        by_job[job_id]["tokens"] += tokens

top = sorted(by_job.items(), key=lambda kv: kv[1]["tokens"], reverse=True)[:3]
top_out = [
    {"jobId": jid, "runs": vals["runs"], "tokens": vals["tokens"]}
    for jid, vals in top
]

print(json.dumps({
    "ok": True,
    "action": "cost_scan_24h",
    "totalRuns24h": total_runs,
    "totalTokens24h": total_tokens,
    "topJobsByTokens": top_out
}, ensure_ascii=False))
PY
