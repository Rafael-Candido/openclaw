#!/usr/bin/env bash
# Executa N rodadas de todos os crons com proteção de autonomia:
# - timeout interno do openclaw + timeout duro do shell
# - retry único em falhas transitórias
# - resumo final por job (ok/fail/latência média e máxima)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_GUARD="${SCRIPT_DIR}/runtime-guard.sh"

if [[ -x "${RUNTIME_GUARD}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_GUARD}"
  if ! ocw_guard_acquire_lock "run-cron-20rounds" "${CRON_LOCK_STALE_SEC:-7200}"; then
    echo '{"ok":true,"action":"skipped_already_running","lock":"run-cron-20rounds"}'
    exit 0
  fi
  trap 'ocw_guard_release_lock' EXIT
fi

ROUNDS="${1:-20}"
CONFIG="${OPENCLAW_CONFIG_DIR:-/private/var/www/openclaw}"
TIMEOUT_MS="${CRON_RUN_TIMEOUT_MS:-120000}"
HARD_TIMEOUT_SEC="${CRON_RUN_HARD_TIMEOUT_SEC:-150}"
RETRY_ON_FAIL="${CRON_RUN_RETRY_ON_FAIL:-1}"
SLEEP_BETWEEN_JOBS_SEC="${CRON_RUN_SLEEP_BETWEEN_JOBS_SEC:-1}"
SLEEP_BETWEEN_ROUNDS_SEC="${CRON_RUN_SLEEP_BETWEEN_ROUNDS_SEC:-1}"
SLOW_JOB_THRESHOLD_SEC="${CRON_RUN_SLOW_JOB_THRESHOLD_SEC:-45}"
FAIL_FAST_THRESHOLD="${CRON_RUN_FAIL_FAST_THRESHOLD:-0}"
JSON_SUMMARY="${CRON_RUN_JSON_SUMMARY:-true}"
MAX_LOG_TAIL_LINES="${CRON_RUN_MAX_LOG_TAIL_LINES:-60}"

LOG="${CONFIG}/workspace/tmp/cron-20rounds-$(date +%Y%m%d-%H%M%S).log"
SUMMARY="${LOG%.log}.summary.txt"
SUMMARY_JSON="${LOG%.log}.summary.json"
mkdir -p "$(dirname "${LOG}")"

CRONS="$(jq -r '.jobs[]? | select(.enabled==true) | .id' "${CONFIG}/cron/jobs.json")"
CRON_COUNT="$(echo "${CRONS}" | wc -w | tr -d ' ')"

detect_timeout_cmd() {
  if command -v gtimeout >/dev/null 2>&1; then
    echo "gtimeout"
    return
  fi
  if command -v timeout >/dev/null 2>&1; then
    echo "timeout"
    return
  fi
  echo ""
}

TIMEOUT_CMD="$(detect_timeout_cmd)"

run_once() {
  local id="$1"
  local tmp_out="$2"
  local rc=0
  if [[ -n "${TIMEOUT_CMD}" ]]; then
    "${TIMEOUT_CMD}" "${HARD_TIMEOUT_SEC}"s openclaw cron run "${id}" --timeout "${TIMEOUT_MS}" >"${tmp_out}" 2>&1 || rc=$?
  else
    openclaw cron run "${id}" --timeout "${TIMEOUT_MS}" >"${tmp_out}" 2>&1 || rc=$?
  fi
  return "${rc}"
}

classify_status() {
  local rc="$1"
  local out_file="$2"
  local status="error"
  if grep -qi 'already-running' "${out_file}"; then
    status="already-running"
  elif grep -qi 'gateway timeout' "${out_file}"; then
    status="gateway-timeout"
  elif grep -qi 'timed out\|timeout' "${out_file}"; then
    status="timeout"
  elif [[ "${rc}" -eq 124 || "${rc}" -eq 137 ]]; then
    status="timeout"
  elif [[ "${rc}" -eq 0 ]] && grep -q '"ok":[[:space:]]*true' "${out_file}"; then
    status="ok"
  elif [[ "${rc}" -eq 0 ]]; then
    status="ran-without-ok-flag"
  fi
  echo "${status}"
}

echo "Início: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" | tee "${LOG}"
echo "Rodadas: ${ROUNDS} | Crons: ${CRON_COUNT}" | tee -a "${LOG}"
echo "Config: timeout_ms=${TIMEOUT_MS} hard_timeout_sec=${HARD_TIMEOUT_SEC} retry_on_fail=${RETRY_ON_FAIL}" | tee -a "${LOG}"
echo "Runner timeout cmd: ${TIMEOUT_CMD:-none}" | tee -a "${LOG}"
echo "SLA: slow_job_threshold_sec=${SLOW_JOB_THRESHOLD_SEC} fail_fast_threshold=${FAIL_FAST_THRESHOLD}" | tee -a "${LOG}"

r=0
global_fail=0
while [[ "${r}" -lt "${ROUNDS}" ]]; do
  r=$((r+1))
  echo "--- Rodada ${r}/${ROUNDS} ---" >> "${LOG}"
  for id in ${CRONS}; do
    start="$(date +%s)"
    ts="$(date -u '+%H:%M:%S')"
    tmp_out="/tmp/cron-run-${id}-r${r}-$$.log"
    run_once "${id}" "${tmp_out}"
    rc=$?
    status="$(classify_status "${rc}" "${tmp_out}")"
    end="$(date +%s)"
    elapsed=$((end - start))

    cat "${tmp_out}" >> "${LOG}" || true
    tail -n "${MAX_LOG_TAIL_LINES}" "${tmp_out}" >/dev/null 2>&1 || true
    echo "${ts} ${id} ${status} ${elapsed}s try=1" >> "${LOG}"
    echo "ROW|${r}|${id}|${status}|${elapsed}|1" >> "${LOG}"
    [[ "${status}" != "ok" ]] && global_fail=$((global_fail+1))

    if [[ "${RETRY_ON_FAIL}" = "1" ]] && [[ "${status}" != "ok" ]] && [[ "${status}" != "already-running" ]]; then
      sleep 1
      start2="$(date +%s)"
      ts2="$(date -u '+%H:%M:%S')"
      run_once "${id}" "${tmp_out}"
      rc2=$?
      status2="$(classify_status "${rc2}" "${tmp_out}")"
      end2="$(date +%s)"
      elapsed2=$((end2 - start2))
      cat "${tmp_out}" >> "${LOG}" || true
      echo "${ts2} ${id} ${status2} ${elapsed2}s try=2" >> "${LOG}"
      echo "ROW|${r}|${id}|${status2}|${elapsed2}|2" >> "${LOG}"
      [[ "${status2}" != "ok" ]] && global_fail=$((global_fail+1))
    fi
    rm -f "${tmp_out}" 2>/dev/null || true
    sleep "${SLEEP_BETWEEN_JOBS_SEC}"
  done
  if [[ "${FAIL_FAST_THRESHOLD}" =~ ^[0-9]+$ ]] && (( FAIL_FAST_THRESHOLD > 0 )) && (( global_fail >= FAIL_FAST_THRESHOLD )); then
    echo "FAIL_FAST acionado: global_fail=${global_fail} threshold=${FAIL_FAST_THRESHOLD}" | tee -a "${LOG}"
    break
  fi
  sleep "${SLEEP_BETWEEN_ROUNDS_SEC}"
done

echo "Fim: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" | tee -a "${LOG}"

{
  echo "Resumo por job:"
  awk -F'|' '
    $1=="ROW"{
      id=$3; st=$4; el=$5+0;
      cnt[id]++; sum[id]+=el;
      vals[id]=vals[id] " " el;
      if (el>max[id]) max[id]=el;
      if (st=="ok") ok[id]++; else fail[id]++;
    }
    function p95(s, n,    a,i,j,tmp,idx){
      split(s,a," "); j=0;
      for(i in a){ if(a[i]!=""){ j++; b[j]=a[i]+0; } }
      for(i=1;i<=j;i++) for(n=i+1;n<=j;n++) if(b[n]<b[i]){ tmp=b[i]; b[i]=b[n]; b[n]=tmp; }
      if (j==0) return 0;
      idx=int((j*95+99)/100); if(idx<1) idx=1; if(idx>j) idx=j;
      return b[idx];
    }
    END{
      for (id in cnt) {
        avg = (cnt[id]>0 ? sum[id]/cnt[id] : 0);
        p95v=p95(vals[id],cnt[id]);
        printf "%s total=%d ok=%d fail=%d avg=%.2fs p95=%ds max=%ds\n", id, cnt[id], ok[id]+0, fail[id]+0, avg, p95v+0, max[id]+0;
      }
    }
  ' "${LOG}" | sort
} | tee "${SUMMARY}"

if [[ "${JSON_SUMMARY}" == "true" ]]; then
  python3 - "${LOG}" "${SLOW_JOB_THRESHOLD_SEC}" "${SUMMARY_JSON}" <<'PY'
import json, sys
from collections import defaultdict
log_path, slow_raw, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
slow = int(slow_raw) if slow_raw.isdigit() else 45
rows = []
with open(log_path, "r", encoding="utf-8", errors="ignore") as fh:
    for ln in fh:
        if not ln.startswith("ROW|"):
            continue
        p = ln.strip().split("|")
        if len(p) != 6:
            continue
        rows.append({
            "round": int(p[1]), "jobId": p[2], "status": p[3],
            "elapsedSec": int(p[4]), "try": int(p[5]),
        })

agg = defaultdict(lambda: {"total":0,"ok":0,"fail":0,"elapsed":[]})
for r in rows:
    a = agg[r["jobId"]]
    a["total"] += 1
    a["ok"] += 1 if r["status"] == "ok" else 0
    a["fail"] += 0 if r["status"] == "ok" else 1
    a["elapsed"].append(r["elapsedSec"])

def p95(vals):
    if not vals: return 0
    vals = sorted(vals)
    idx = (len(vals) * 95 + 99) // 100 - 1
    idx = max(0, min(idx, len(vals)-1))
    return vals[idx]

jobs = []
slow_jobs = []
for job, data in sorted(agg.items()):
    avg = (sum(data["elapsed"]) / len(data["elapsed"])) if data["elapsed"] else 0.0
    mx = max(data["elapsed"]) if data["elapsed"] else 0
    p = p95(data["elapsed"])
    item = {
        "jobId": job,
        "total": data["total"],
        "ok": data["ok"],
        "fail": data["fail"],
        "avgSec": round(avg, 2),
        "p95Sec": p,
        "maxSec": mx
    }
    jobs.append(item)
    if mx >= slow or p >= slow:
        slow_jobs.append(item)

summary = {
    "ok": True,
    "action": "cron_20rounds_summary",
    "rows": len(rows),
    "roundsSeen": len({r["round"] for r in rows}),
    "totalFail": sum(1 for r in rows if r["status"] != "ok"),
    "slowThresholdSec": slow,
    "jobs": jobs,
    "slowJobs": slow_jobs
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(summary, fh, ensure_ascii=False, indent=2)
PY
fi

echo "Log: ${LOG}"
echo "Summary: ${SUMMARY}"
[[ -f "${SUMMARY_JSON}" ]] && echo "Summary JSON: ${SUMMARY_JSON}"
