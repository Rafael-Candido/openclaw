#!/usr/bin/env bash
set -euo pipefail

# cron-safe-run.sh
# Runner manual com circuit breaker para evitar tempestade de timeouts no gateway.
# Uso:
#   workspace/scripts/cron-safe-run.sh                # 1 ciclo em todos os crons habilitados
#   workspace/scripts/cron-safe-run.sh --cycles 2     # 2 ciclos
#   workspace/scripts/cron-safe-run.sh --ids "id1 id2"

CYCLES=1
TIMEOUT_MS="${CRON_SAFE_TIMEOUT_MS:-45000}"
GAP_SEC="${CRON_SAFE_GAP_SEC:-2}"
COOLDOWN_SEC="${CRON_SAFE_COOLDOWN_SEC:-20}"
CB_MIN_ATTEMPTS="${CRON_SAFE_CB_MIN_ATTEMPTS:-4}"
CB_TIMEOUT_RATIO_PCT="${CRON_SAFE_CB_TIMEOUT_RATIO_PCT:-50}"
IDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cycles) CYCLES="$2"; shift 2 ;;
    --timeout-ms) TIMEOUT_MS="$2"; shift 2 ;;
    --gap-sec) GAP_SEC="$2"; shift 2 ;;
    --ids) IDS="$2"; shift 2 ;;
    *) echo "Parâmetro inválido: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$IDS" ]]; then
  IDS="$(openclaw cron list --json | jq -r '.jobs[] | select(.enabled==true) | .id' | xargs)"
fi

if [[ -z "${IDS//[[:space:]]/}" ]]; then
  echo "Nenhum cron habilitado encontrado."
  exit 0
fi

echo "ids=${IDS}"

timeout_count=0
attempt_count=0

for ((cycle=1; cycle<=CYCLES; cycle++)); do
  echo "== cycle=${cycle} $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
  for id in $IDS; do
    name="$(jq -r --arg id "$id" '.jobs[] | select(.id==$id) | .name' ~/.openclaw/cron/jobs.json 2>/dev/null || echo "$id")"
    out="$(openclaw cron run "$id" --timeout "$TIMEOUT_MS" 2>&1 || true)"
    attempt_count=$((attempt_count+1))
    status="ok"
    if grep -qi 'gateway timeout' <<<"$out"; then
      status="gateway-timeout"
      timeout_count=$((timeout_count+1))
    elif grep -qi 'already-running' <<<"$out"; then
      status="already-running"
    elif ! grep -q '"ok": true' <<<"$out"; then
      status="error"
    fi
    echo "cron|$id|$name|$status"

    if (( attempt_count >= CB_MIN_ATTEMPTS )); then
      ratio=$((timeout_count * 100 / attempt_count))
      if (( ratio >= CB_TIMEOUT_RATIO_PCT )); then
        echo "circuit-breaker|triggered|timeouts=${timeout_count}/${attempt_count}|ratio=${ratio}%|cooldown=${COOLDOWN_SEC}s"
        sleep "$COOLDOWN_SEC"
        timeout_count=0
        attempt_count=0
      fi
    fi

    sleep "$GAP_SEC"
  done
done
