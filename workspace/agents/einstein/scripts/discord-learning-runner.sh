#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_SCRIPT="${SCRIPT_DIR}/discord-learning-session.sh"

MAX_SESSIONS="${MAX_SESSIONS:-20}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"
PASS_ARGS=()

usage() {
  cat <<'EOF'
Uso:
  discord-learning-runner.sh [--max-sessions N] [--sleep-seconds N] [args da session...]

Exemplo:
  discord-learning-runner.sh --max-sessions 12 --sleep-seconds 3 --max-channels 8 --max-pages-per-channel 8 --limit 50
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-sessions)
      MAX_SESSIONS="${2:-}"
      shift 2
      ;;
    --sleep-seconds)
      SLEEP_SECONDS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      PASS_ARGS+=("$1")
      shift
      ;;
  esac
done

if ! [[ "${MAX_SESSIONS}" =~ ^[0-9]+$ ]] || (( MAX_SESSIONS < 1 )); then
  echo "max-sessions invalido: ${MAX_SESSIONS}" >&2
  exit 1
fi
if ! [[ "${SLEEP_SECONDS}" =~ ^[0-9]+$ ]] || (( SLEEP_SECONDS < 0 )); then
  echo "sleep-seconds invalido: ${SLEEP_SECONDS}" >&2
  exit 1
fi

total_messages=0
total_qa=0

for ((i = 1; i <= MAX_SESSIONS; i++)); do
  run_output="$("${SESSION_SCRIPT}" --output json "${PASS_ARGS[@]}")"
  echo "${run_output}"

  messages="$(jq -r '.messagesScanned // 0' <<<"${run_output}")"
  qa="$(jq -r '.qaPairsAdded // 0' <<<"${run_output}")"
  pending="$(jq -r '.channelsPending // -1' <<<"${run_output}")"
  processed="$(jq -r '.channelsProcessed // 0' <<<"${run_output}")"
  timestamp="$(jq -r '.sessionAt // ""' <<<"${run_output}")"

  total_messages=$((total_messages + messages))
  total_qa=$((total_qa + qa))

  echo "runner: sessao=${i} at=${timestamp} processed=${processed} pending=${pending} messages=${messages} qa=${qa} acumulado_messages=${total_messages} acumulado_qa=${total_qa}"

  if (( pending == 0 )); then
    echo "runner: aprendizado completo para canais elegiveis."
    break
  fi
  if (( processed == 0 )); then
    echo "runner: nenhuma mudanca de processamento nesta sessao, encerrando para evitar loop."
    break
  fi

  if (( i < MAX_SESSIONS && SLEEP_SECONDS > 0 )); then
    sleep "${SLEEP_SECONDS}"
  fi
done

