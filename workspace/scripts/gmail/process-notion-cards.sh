#!/usr/bin/env bash
# Unified Mail-Pro / Mail-Person processing for Notion cards.

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-15}"

ROOT="/var/www/openclaw/workspace"
NOTION_HELPER="${ROOT}/scripts/notion-helper.sh"
PROCESS_WORKFLOW="${ROOT}/scripts/gmail/process-workflow.sh"
GMAIL_SCRIPT="${ROOT}/scripts/gmail/gmail.sh"
LOCK_DIR="/tmp/openclaw-mail-${PROFILE}.lockdir"
BATCH_STATE_FILE="/tmp/openclaw-mail-${PROFILE}-batch-state.json"

if [[ ! -x "${NOTION_HELPER}" || ! -x "${PROCESS_WORKFLOW}" || ! -x "${GMAIL_SCRIPT}" ]]; then
  echo '{"error":"required scripts not found"}'
  exit 1
fi

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  jq -n \
    --arg profile "${PROFILE}" \
    --arg message "execucao-ja-em-andamento" \
    '{profile:$profile,processed:0,success:0,partial:0,failed:0,message:$message}'
  exit 0
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

case "${PROFILE}" in
  pro)
    DB_ID="adec12e735dc41a3bb7c274b287f3a10"
    API_KEY_VAR="NOTION_SMARTENVIOS_API_KEY"
    AGENT_NAME="Mail-Pro"
    MAILBOX="rafael.pereira@smartenvios.com"
    ;;
  personal)
    DB_ID="bfcbe7a7a3a745489e605e0762af12a9"
    API_KEY_VAR="NOTION_PERSONAL_API_KEY"
    AGENT_NAME="Mail-Person"
    MAILBOX="rafael.silva.pereira10@gmail.com"
    ;;
  *)
    echo "{\"error\":\"unsupported profile: ${PROFILE}\"}"
    exit 1
    ;;
esac

normalize_positive_int() {
  local value="$1"
  local fallback="$2"
  if [[ "${value}" =~ ^[0-9]+$ ]] && (( value > 0 )); then
    echo "${value}"
  else
    echo "${fallback}"
  fi
}

load_batch_state() {
  local fallback_limit="$1"
  LAST_LIMIT="${fallback_limit}"
  LAST_STATUS="idle"
  SUCCESS_STREAK=0
  LAST_DURATION_SEC=0

  [[ -f "${BATCH_STATE_FILE}" ]] || return 0

  LAST_LIMIT="$(jq -r '.lastLimit // empty' "${BATCH_STATE_FILE}" 2>/dev/null || true)"
  LAST_STATUS="$(jq -r '.lastStatus // "idle"' "${BATCH_STATE_FILE}" 2>/dev/null || echo "idle")"
  SUCCESS_STREAK="$(jq -r '.successStreak // 0' "${BATCH_STATE_FILE}" 2>/dev/null || echo 0)"
  LAST_DURATION_SEC="$(jq -r '.lastDurationSec // 0' "${BATCH_STATE_FILE}" 2>/dev/null || echo 0)"

  LAST_LIMIT="$(normalize_positive_int "${LAST_LIMIT}" "${fallback_limit}")"
  SUCCESS_STREAK="$(normalize_positive_int "${SUCCESS_STREAK}" 0)"
  LAST_DURATION_SEC="$(normalize_positive_int "${LAST_DURATION_SEC}" 0)"
}

save_batch_state() {
  local status="$1"
  local used_limit="$2"
  local unread_estimate="$3"
  local duration_sec="$4"
  local next_streak="${SUCCESS_STREAK:-0}"

  used_limit="$(normalize_positive_int "${used_limit}" 15)"
  unread_estimate="$(normalize_positive_int "${unread_estimate}" 0)"
  duration_sec="$(normalize_positive_int "${duration_sec}" 0)"
  next_streak="$(normalize_positive_int "${next_streak}" 0)"

  case "${status}" in
    success)
      next_streak=$((next_streak + 1))
      ;;
    partial|failed)
      next_streak=0
      ;;
    idle)
      next_streak=0
      ;;
    *)
      ;;
  esac

  jq -n \
    --arg status "${status}" \
    --argjson lastLimit "${used_limit}" \
    --argjson successStreak "${next_streak}" \
    --argjson lastDurationSec "${duration_sec}" \
    --argjson lastUnreadEstimate "${unread_estimate}" \
    --argjson updatedAt "$(date +%s)" \
    '{
      lastStatus:$status,
      lastLimit:$lastLimit,
      successStreak:$successStreak,
      lastDurationSec:$lastDurationSec,
      lastUnreadEstimate:$lastUnreadEstimate,
      updatedAt:$updatedAt
    }' > "${BATCH_STATE_FILE}.tmp" \
    && mv "${BATCH_STATE_FILE}.tmp" "${BATCH_STATE_FILE}"
}

resolve_effective_limit() {
  local base_limit="$1"
  local effective_limit unread_estimate raw_count
  local min_limit max_limit step_up step_down success_streak_needed slow_run_sec
  local target_limit

  base_limit="$(normalize_positive_int "${base_limit}" 15)"
  min_limit="$(normalize_positive_int "${MAIL_BATCH_MIN_LIMIT:-5}" 5)"
  max_limit="$(normalize_positive_int "${MAIL_BATCH_MAX_LIMIT:-20}" 20)"
  step_up="$(normalize_positive_int "${MAIL_BATCH_STEP_UP:-5}" 5)"
  step_down="$(normalize_positive_int "${MAIL_BATCH_STEP_DOWN:-5}" 5)"
  success_streak_needed="$(normalize_positive_int "${MAIL_BATCH_SUCCESS_STREAK:-2}" 2)"
  slow_run_sec="$(normalize_positive_int "${MAIL_BATCH_SLOW_RUN_SEC:-180}" 180)"

  if (( max_limit < min_limit )); then
    max_limit="${min_limit}"
  fi
  if (( base_limit < min_limit )); then
    base_limit="${min_limit}"
  fi
  if (( base_limit > max_limit )); then
    base_limit="${max_limit}"
  fi

  raw_count="$("${GMAIL_SCRIPT}" "${PROFILE}" list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
  unread_estimate=0
  if [[ "${raw_count}" =~ ^[0-9]+$ ]]; then
    unread_estimate="${raw_count}"
  fi

  # Escalonamento alvo por backlog com teto conservador; a rampa decide como chegar.
  target_limit="${base_limit}"
  if (( unread_estimate >= 250 )); then
    target_limit="${max_limit}"
  elif (( unread_estimate >= 160 )); then
    target_limit=$((base_limit + (step_up * 2)))
  elif (( unread_estimate >= 100 )); then
    target_limit=$((base_limit + step_up))
  fi
  if (( target_limit > max_limit )); then
    target_limit="${max_limit}"
  fi

  load_batch_state "${base_limit}"
  effective_limit="${base_limit}"

  if [[ "${LAST_STATUS}" == "failed" || "${LAST_STATUS}" == "partial" ]]; then
    # Queda imediata após erro parcial/falha para evitar repetição de crash.
    effective_limit=$((LAST_LIMIT - step_down))
  elif (( LAST_DURATION_SEC >= slow_run_sec )) && (( LAST_LIMIT > base_limit )); then
    # Run anterior muito lenta: recua 1 passo para estabilizar.
    effective_limit=$((LAST_LIMIT - step_down))
  elif [[ "${LAST_STATUS}" == "success" ]] && (( SUCCESS_STREAK >= success_streak_needed )) && (( LAST_LIMIT < target_limit )); then
    # Sobe de forma gradual somente após sequência de sucesso.
    effective_limit=$((LAST_LIMIT + step_up))
  elif (( LAST_LIMIT < base_limit )); then
    # Recupera para o base quando já estabilizou.
    effective_limit=$((LAST_LIMIT + step_up))
  else
    effective_limit="${LAST_LIMIT}"
  fi

  if (( effective_limit > target_limit )); then
    effective_limit="${target_limit}"
  fi
  if (( effective_limit < min_limit )); then
    effective_limit="${min_limit}"
  fi
  if (( effective_limit > max_limit )); then
    effective_limit="${max_limit}"
  fi

  echo "${effective_limit}|${unread_estimate}"
}

QUERY_OUT="$("${NOTION_HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${AGENT_NAME}" Priorizado "Em andamento")"
CARDS_FOUND="$(echo "${QUERY_OUT}" | jq -r '.results | length')"

if [[ "${CARDS_FOUND}" == "0" ]]; then
  LIMIT_INFO="$(resolve_effective_limit "${LIMIT}")"
  EFFECTIVE_LIMIT="${LIMIT_INFO%%|*}"
  BACKLOG_ESTIMATE="${LIMIT_INFO##*|}"
  save_batch_state "idle" "${LIMIT}" "${BACKLOG_ESTIMATE}" 0
  jq -n \
    --arg profile "${PROFILE}" \
    --arg agent "${AGENT_NAME}" \
    --arg mailbox "${MAILBOX}" \
    --argjson backlog "${BACKLOG_ESTIMATE}" \
    --argjson baseLimit "${LIMIT}" \
    --argjson effectiveLimit "${EFFECTIVE_LIMIT}" \
    '{profile:$profile,agent:$agent,mailbox:$mailbox,cardsFound:0,processed:0,success:0,partial:0,failed:0,backlogEstimate:$backlog,baseLimit:$baseLimit,effectiveLimit:$effectiveLimit,message:"nenhum card encontrado"}'
  exit 0
fi

SUCCESS=0
PARTIAL=0
FAILED=0
PROCESSED=0
CARDS_SUMMARY='[]'

while IFS= read -r CARD; do
  [[ -z "${CARD}" ]] && continue

  PAGE_ID="$(echo "${CARD}" | jq -r '.id')"
  CARD_TITLE="$(echo "${CARD}" | jq -r '.properties.Name.title[0].plain_text // "Sem título"')"
  CARD_STATUS="$(echo "${CARD}" | jq -r '.properties.Status.select.name // ""')"
  RESULT_FILE="/tmp/mail-${PROFILE}-${PAGE_ID//-/}.json"
  CARD_RESULT="failed"
  NOTE=""
  LIMIT_INFO="$(resolve_effective_limit "${LIMIT}")"
  EFFECTIVE_LIMIT="${LIMIT_INFO%%|*}"
  BACKLOG_ESTIMATE="${LIMIT_INFO##*|}"

  if [[ "${CARD_STATUS}" == "Priorizado" ]]; then
    "${NOTION_HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Em andamento" >/dev/null
  fi

  "${NOTION_HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Início da execução: triagem unificada com labels, leitura, rascunhos e arquivamento (lote base=${LIMIT}, lote efetivo=${EFFECTIVE_LIMIT}, backlog estimado=${BACKLOG_ESTIMATE})." "${AGENT_NAME}" >/dev/null

  RUN_STARTED_AT="$(date +%s)"
  if "${PROCESS_WORKFLOW}" "${PROFILE}" "${EFFECTIVE_LIMIT}" > "${RESULT_FILE}"; then
    ERROR_COUNT="$(jq -r '.errors | length' "${RESULT_FILE}")"
    if [[ "${ERROR_COUNT}" == "0" ]]; then
      RESULT_STATUS="Sucesso"
      CARD_RESULT="success"
      SUCCESS=$((SUCCESS + 1))
      "${NOTION_HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Concluído" >/dev/null
    else
      RESULT_STATUS="Sucesso parcial"
      CARD_RESULT="partial"
      PARTIAL=$((PARTIAL + 1))
      NOTE="erros durante execução; card mantido em Em andamento"
    fi

    FINAL_COMMENT="$(jq -r \
      --arg mailbox "${MAILBOX}" \
      --arg resultStatus "${RESULT_STATUS}" \
      --arg baseLimit "${LIMIT}" \
      --arg effectiveLimit "${EFFECTIVE_LIMIT}" \
      --arg backlogEstimate "${BACKLOG_ESTIMATE}" '
      def evidence_lines:
        (if (.evidences | length) == 0 then
          "- sem evidências no lote"
        else
          (.evidences[:5] | map("- " + .messageId + ": " + .subject) | join("\n"))
        end);
      "## Resultado executivo\n" +
      "- Status: " + $resultStatus + "\n" +
      "- Caixa analisada: " + $mailbox + "\n" +
      "- Janela/consulta usada: " + .query + "\n" +
      "## Métricas\n" +
      "- Não lidos encontrados: " + (.totalUnread|tostring) + "\n" +
      "- Backlog estimado antes da rodada: " + $backlogEstimate + "\n" +
      "- Lote executado: base=" + $baseLimit + " / efetivo=" + $effectiveLimit + "\n" +
      "- E-mails lidos com histórico: " + (.triaged|tostring) + "\n" +
      "- Triados: " + (.triaged|tostring) + " (Importante=" + (.counts.draft|tostring) + ", Aguardando=" + (.counts.review|tostring) + ", BaixoValor=" + (.counts.label|tostring) + ")\n" +
      "- Labels reaproveitadas: " + ((.labelsReused // [])|tostring) + "\n" +
      "- Labels criadas: " + ((.labelsCreated // [])|tostring) + "\n" +
      "- E-mails marcados como lidos: " + (.markedRead|tostring) + "\n" +
      "- Arquivados: " + (.archived|tostring) + "\n" +
      "- Rascunhos criados: " + (.draftsCreated|tostring) + "\n" +
      "## Evidências\n" + evidence_lines + "\n" +
      "## Decisões e próximos passos\n" +
      "- Critérios aplicados: classificação por action draft/review/label/ignore com execução real no Gmail.\n" +
      "- Pendências: " + (if (.errors|length)==0 then "sem bloqueios nesta rodada." else "verificar erros registrados no lote atual." end)
    ' "${RESULT_FILE}")"

    "${NOTION_HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "${FINAL_COMMENT}" "${AGENT_NAME}" >/dev/null
  else
    CARD_RESULT="failed"
    FAILED=$((FAILED + 1))
    NOTE="falha ao executar process-workflow.sh"
    "${NOTION_HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Falha na execução do workflow unificado. Card mantido em Em andamento para nova tentativa." "${AGENT_NAME}" >/dev/null
  fi
  RUN_DURATION_SEC=$(( $(date +%s) - RUN_STARTED_AT ))
  save_batch_state "${CARD_RESULT}" "${EFFECTIVE_LIMIT}" "${BACKLOG_ESTIMATE}" "${RUN_DURATION_SEC}"

  PROCESSED=$((PROCESSED + 1))
  CARDS_SUMMARY="$(echo "${CARDS_SUMMARY}" | jq \
    --arg id "${PAGE_ID}" \
    --arg title "${CARD_TITLE}" \
    --arg result "${CARD_RESULT}" \
    --arg note "${NOTE}" \
    '. + [{id:$id,title:$title,result:$result,note:$note}]')"
done < <(echo "${QUERY_OUT}" | jq -c '.results[]')

jq -n \
  --arg profile "${PROFILE}" \
  --arg agent "${AGENT_NAME}" \
  --arg mailbox "${MAILBOX}" \
  --argjson cardsFound "${CARDS_FOUND}" \
  --argjson processed "${PROCESSED}" \
  --argjson success "${SUCCESS}" \
  --argjson partial "${PARTIAL}" \
  --argjson failed "${FAILED}" \
  --argjson cards "${CARDS_SUMMARY}" \
  '{profile:$profile,agent:$agent,mailbox:$mailbox,cardsFound:$cardsFound,processed:$processed,success:$success,partial:$partial,failed:$failed,cards:$cards}'
