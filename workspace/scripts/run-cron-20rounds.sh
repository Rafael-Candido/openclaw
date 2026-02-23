#!/usr/bin/env bash
# Executa N rodadas de todos os crons (cron run) e regista duração/status.
set -euo pipefail
ROUNDS="${1:-20}"
CONFIG="${OPENCLAW_CONFIG_DIR:-/private/var/www/openclaw}"
LOG="${CONFIG}/workspace/tmp/cron-20rounds-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
CRONS="$(jq -r '.jobs[]? | .id' "${CONFIG}/cron/jobs.json")"
echo "Início: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" | tee "$LOG"
echo "Rodadas: $ROUNDS | Crons: $(echo $CRONS | wc -w)" | tee -a "$LOG"
r=0
while [[ $r -lt $ROUNDS ]]; do
  r=$((r+1))
  echo "--- Rodada $r/$ROUNDS ---" >> "$LOG"
  for id in $CRONS; do
    start=$(date +%s)
    if openclaw cron run "$id" --timeout 120000 >> "$LOG" 2>&1; then
      status=ok
    else
      status=fail
    fi
    end=$(date +%s)
    elapsed=$((end - start))
    echo "$(date -u '+%H:%M:%S') $id $status ${elapsed}s" >> "$LOG"
  done
done
echo "Fim: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" | tee -a "$LOG"
echo "Log: $LOG"
