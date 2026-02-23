#!/usr/bin/env bash
# Analisa logs de execução dos crons (cron/runs/*.jsonl) e extrai:
# - duração (durationMs), status, erros, tendências
# - gargalos (crons mais lentos, mais erros, timeouts)
# Uso: ./scripts/analyze-cron-logs.sh [rodadas]   (default: últimas 20 por cron)

set -euo pipefail

ROUNDS="${1:-20}"
RUNS_DIR="${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}/cron/runs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ ! -d "${RUNS_DIR}" ]]; then
  echo "Diretório de runs não encontrado: ${RUNS_DIR}" >&2
  exit 1
fi

echo "=== Análise de logs dos crons (últimas ${ROUNDS} rodadas por job) ==="
echo "Data: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo ""

# Nomes: extrair do jobs.json
JOBS_JSON="${PROJECT_ROOT}/cron/jobs.json"
get_job_name() {
  local id="$1"
  [[ -f "${JOBS_JSON}" ]] || echo "$id"
  jq -r --arg id "${id}" '.jobs[]? | select(.id==$id) | .name // $id' "${JOBS_JSON}" 2>/dev/null || echo "$id"
}

SUMMARY_FILE="${PROJECT_ROOT}/workspace/tmp/cron-logs-summary-$$.json"
mkdir -p "$(dirname "${SUMMARY_FILE}")"
echo '{"jobs":{},"gargalos":[],"totals":{}}' > "${SUMMARY_FILE}"

for run_file in "${RUNS_DIR}"/*.jsonl; do
  [[ -f "$run_file" ]] || continue
  job_id="$(basename "${run_file}" .jsonl)"
  job_name="$(get_job_name "${job_id}")"

  # Últimas N linhas com action=finished
  sample="$(tail -n 500 "${run_file}" 2>/dev/null | grep '"action":"finished"' | tail -n "${ROUNDS}")"
  if [[ -z "${sample}" ]]; then
    continue
  fi

  # Extrair durationMs, status
  stats="$(echo "${sample}" | jq -s '
    [.[] | {durationMs: (.durationMs // 0), status: (.status // "unknown")}]
    | {
        count: length,
        ok: [.[] | select(.status == "ok")] | length,
        error: [.[] | select(.status == "error" or .status == "failed" or .status == "timeout")] | length,
        durationMs: (([.[] | .durationMs] | add) / length),
        durationMin: ([.[] | .durationMs] | min / 60000),
        durationMax: ([.[] | .durationMs] | max / 60000)
      }
  ' 2>/dev/null || echo '{}')"

  count="$(echo "$stats" | jq -r '.count // 0')"
  ok="$(echo "$stats" | jq -r '.ok // 0')"
  err="$(echo "$stats" | jq -r '.error // 0')"
  avg_ms="$(echo "$stats" | jq -r '.durationMs // 0')"
  max_ms="$(echo "$stats" | jq -r '.durationMax // 0')"
  avg_sec="$(echo "scale=2; ${avg_ms}/1000" | bc 2>/dev/null || echo "0")"
  max_sec="$(echo "scale=2; ${max_ms}/1000" | bc 2>/dev/null || echo "0")"

  echo "--- ${job_name} (${job_id}) ---"
  echo "  Rodadas: ${count} | OK: ${ok} | Erro: ${err}"
  echo "  Duração: média ${avg_sec}s | máx ${max_sec}s"
  echo ""

  jq --arg id "${job_id}" \
     --arg name "${job_name}" \
     --argjson count "${count}" \
     --argjson ok "${ok}" \
     --argjson err "${err}" \
     --argjson avgMs "${avg_ms}" \
     --argjson maxMs "${max_ms}" \
     '.jobs[$id] = {name:$name,count:$count,ok:$ok,error:$err,avgDurationMs:$avgMs,maxDurationMs:$maxMs}' \
     "${SUMMARY_FILE}" > "${SUMMARY_FILE}.tmp" && mv "${SUMMARY_FILE}.tmp" "${SUMMARY_FILE}"
done

echo "=== Gargalos (avg > 30s ou erros > 0) ==="
jq -r '
  .jobs | to_entries[] |
  select(.value.avgDurationMs > 30000 or (.value.error > 0)) |
  "  - \(.value.name): avg=\(.value.avgDurationMs/1000)s, erros=\(.value.error)"
' "${SUMMARY_FILE}" 2>/dev/null || true

echo ""
echo "Resumo: ${SUMMARY_FILE}"
