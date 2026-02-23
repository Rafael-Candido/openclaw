#!/usr/bin/env bash
# Execute workflow.sh and apply concrete Gmail actions (draft/label/archive).

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-15}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="${SCRIPT_DIR}/workflow.sh"
GMAIL="${SCRIPT_DIR}/gmail.sh"

if [[ ! -x "${WORKFLOW}" || ! -x "${GMAIL}" ]]; then
  echo '{"error":"required scripts not found"}'
  exit 1
fi

case "${PROFILE}" in
  pro)
    LABEL_PREFIX="Mail-Pro"
    ;;
  personal)
    LABEL_PREFIX="Mail-Person"
    ;;
  *)
    echo "{\"error\":\"unsupported profile: ${PROFILE}\"}"
    exit 1
    ;;
esac

QUERY_CMD="/var/www/openclaw/workspace/scripts/gmail/workflow.sh ${PROFILE} ${LIMIT}"

add_error() {
  local kind="$1"
  local msg_id="$2"
  local detail="$3"
  ERRORS="$(echo "${ERRORS}" | jq --arg k "${kind}" --arg m "${msg_id}" --arg d "${detail}" '. + [{kind:$k,messageId:$m,detail:$d}]')"
}

register_label_state() {
  local name="$1"
  local existed="$2"
  if [[ "${existed}" == "true" ]]; then
    LABELS_REUSED="$(echo "${LABELS_REUSED}" | jq --arg n "${name}" '. + [$n]')"
  else
    LABELS_CREATED="$(echo "${LABELS_CREATED}" | jq --arg n "${name}" '. + [$n]')"
  fi
}

extract_email() {
  local raw="$1"
  local parsed=""
  parsed="$(printf '%s' "${raw}" | sed -n 's/.*<\([^>]*\)>.*/\1/p')"
  if [[ -z "${parsed}" ]]; then
    parsed="$(printf '%s' "${raw}" | sed -nE 's/.*([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}).*/\1/p')"
  fi
  printf '%s' "${parsed}"
}

# Rascunho alinhado ao rafael-dna: frases curtas, sem floreio, sem "obrigado pela mensagem" nem resumo de contexto.
# Ref: workspace/docs/rafael-dna.md (Estilo de Comunicação), communication-patterns-from-samples.md
build_draft_body() {
  local subject="$1"
  local snippet="$2"
  # Corpo mínimo: confirmação e próximo passo. O thread já tem o contexto; não repetir snippet.
  cat <<EOF
Recebi. Retorno em breve.

Rafael
EOF
}

WORKFLOW_OUT="$("${WORKFLOW}" "${PROFILE}" "${LIMIT}")"
TOTAL="$(echo "${WORKFLOW_OUT}" | jq -r '.total // 0')"
TRIAGED="$(echo "${WORKFLOW_OUT}" | jq -r '.processed | length')"
COUNT_DRAFT="$(echo "${WORKFLOW_OUT}" | jq -r '[.processed[] | select(.priority.action == "draft")] | length')"
COUNT_REVIEW="$(echo "${WORKFLOW_OUT}" | jq -r '[.processed[] | select(.priority.action == "review")] | length')"
COUNT_LABEL="$(echo "${WORKFLOW_OUT}" | jq -r '[.processed[] | select(.priority.action == "label")] | length')"
COUNT_IGNORE="$(echo "${WORKFLOW_OUT}" | jq -r '[.processed[] | select(.priority.action == "ignore")] | length')"
WORKFLOW_SUMMARY="$(echo "${WORKFLOW_OUT}" | jq '.summary // {}')"

ERRORS='[]'
EVIDENCES='[]'

DRAFTS_CREATED=0
ARCHIVED=0
MARKED_READ=0
APPLIED_IMPORTANT=0
APPLIED_AGUARDANDO=0
APPLIED_BAIXO=0

LABEL_IMPORTANT_ID=""
LABEL_AGUARDANDO_ID=""
LABEL_BAIXO_ID=""
LABEL_IMPORTANT_EXISTED="false"
LABEL_AGUARDANDO_EXISTED="false"
LABEL_BAIXO_EXISTED="false"
LABELS_REUSED='[]'
LABELS_CREATED='[]'

if [[ "${TOTAL}" != "0" ]]; then
  LABEL_IMPORTANT_RAW="$("${GMAIL}" "${PROFILE}" label-create "${LABEL_PREFIX}-Importante")"
  LABEL_AGUARDANDO_RAW="$("${GMAIL}" "${PROFILE}" label-create "${LABEL_PREFIX}-Aguardando")"
  LABEL_BAIXO_RAW="$("${GMAIL}" "${PROFILE}" label-create "${LABEL_PREFIX}-BaixoValor")"

  LABEL_IMPORTANT_ID="$(echo "${LABEL_IMPORTANT_RAW}" | jq -r '.id // empty')"
  LABEL_AGUARDANDO_ID="$(echo "${LABEL_AGUARDANDO_RAW}" | jq -r '.id // empty')"
  LABEL_BAIXO_ID="$(echo "${LABEL_BAIXO_RAW}" | jq -r '.id // empty')"
  LABEL_IMPORTANT_EXISTED="$(echo "${LABEL_IMPORTANT_RAW}" | jq -r '.existed // false')"
  LABEL_AGUARDANDO_EXISTED="$(echo "${LABEL_AGUARDANDO_RAW}" | jq -r '.existed // false')"
  LABEL_BAIXO_EXISTED="$(echo "${LABEL_BAIXO_RAW}" | jq -r '.existed // false')"

  if [[ -z "${LABEL_IMPORTANT_ID}" ]]; then
    add_error "label-create" "" "${LABEL_PREFIX}-Importante"
  else
    register_label_state "${LABEL_PREFIX}-Importante" "${LABEL_IMPORTANT_EXISTED}"
  fi
  if [[ -z "${LABEL_AGUARDANDO_ID}" ]]; then
    add_error "label-create" "" "${LABEL_PREFIX}-Aguardando"
  else
    register_label_state "${LABEL_PREFIX}-Aguardando" "${LABEL_AGUARDANDO_EXISTED}"
  fi
  if [[ -z "${LABEL_BAIXO_ID}" ]]; then
    add_error "label-create" "" "${LABEL_PREFIX}-BaixoValor"
  else
    register_label_state "${LABEL_PREFIX}-BaixoValor" "${LABEL_BAIXO_EXISTED}"
  fi

  while IFS= read -r item; do
    [[ -z "${item}" ]] && continue

    msg_id="$(echo "${item}" | jq -r '.messageId // ""')"
    subject="$(echo "${item}" | jq -r '.subject // ""')"
    sender="$(echo "${item}" | jq -r '.from // ""')"
    thread_id="$(echo "${item}" | jq -r '.threadId // ""')"
    action="$(echo "${item}" | jq -r '.priority.action // "ignore"')"
    snippet="$(echo "${item}" | jq -r '.snippet // ""' | tr '\n' ' ' | cut -c1-280)"

    EVIDENCES="$(echo "${EVIDENCES}" | jq --arg id "${msg_id}" --arg s "${subject}" --arg a "${action}" '. + [{messageId:$id,subject:$s,action:$a}]')"

    case "${action}" in
      draft)
        to_email="$(extract_email "${sender}")"
        if [[ -z "${to_email}" ]]; then
          add_error "draft-create" "${msg_id}" "could not parse sender email"
        else
          draft_body="$(build_draft_body "${subject}" "${snippet}")"
          if "${GMAIL}" "${PROFILE}" draft-create "${to_email}" "Re: ${subject}" "${draft_body}" "${thread_id}" >/dev/null 2>&1; then
            DRAFTS_CREATED=$((DRAFTS_CREATED + 1))
          else
            add_error "draft-create" "${msg_id}" "gmail.sh draft-create failed"
          fi
        fi
        if [[ -n "${LABEL_IMPORTANT_ID}" ]]; then
          if "${GMAIL}" "${PROFILE}" label-apply "${msg_id}" "${LABEL_IMPORTANT_ID}" >/dev/null 2>&1; then
            APPLIED_IMPORTANT=$((APPLIED_IMPORTANT + 1))
          else
            add_error "label-apply" "${msg_id}" "${LABEL_PREFIX}-Importante"
          fi
        fi
        ;;
      review)
        if [[ -n "${LABEL_AGUARDANDO_ID}" ]]; then
          if "${GMAIL}" "${PROFILE}" label-apply "${msg_id}" "${LABEL_AGUARDANDO_ID}" >/dev/null 2>&1; then
            APPLIED_AGUARDANDO=$((APPLIED_AGUARDANDO + 1))
          else
            add_error "label-apply" "${msg_id}" "${LABEL_PREFIX}-Aguardando"
          fi
        fi
        ;;
      label)
        if [[ -n "${LABEL_BAIXO_ID}" ]]; then
          if "${GMAIL}" "${PROFILE}" label-apply "${msg_id}" "${LABEL_BAIXO_ID}" >/dev/null 2>&1; then
            APPLIED_BAIXO=$((APPLIED_BAIXO + 1))
          else
            add_error "label-apply" "${msg_id}" "${LABEL_PREFIX}-BaixoValor"
          fi
        fi
        ;;
      ignore)
        ;;
      *)
        add_error "action" "${msg_id}" "unknown action: ${action}"
        ;;
    esac
  done < <(echo "${WORKFLOW_OUT}" | jq -c '.processed[]')

  # Batch mark-read e archive (paralelo; menos round-trips)
  BATCH_IDS=()
  while IFS= read -r id; do [[ -n "$id" ]] && BATCH_IDS+=("$id"); done < <(echo "${WORKFLOW_OUT}" | jq -r '.processed[].messageId // empty')
  if [[ ${#BATCH_IDS[@]} -gt 0 ]]; then
    MARKED_READ="$("${GMAIL}" "${PROFILE}" batch-mark-read "${BATCH_IDS[@]}" 2>/dev/null | jq -r '.modified // 0')"
    ARCHIVED="$("${GMAIL}" "${PROFILE}" batch-archive "${BATCH_IDS[@]}" 2>/dev/null | jq -r '.archived // 0')"
    [[ ! "${MARKED_READ}" =~ ^[0-9]+$ ]] && MARKED_READ=${#BATCH_IDS[@]}
    [[ ! "${ARCHIVED}" =~ ^[0-9]+$ ]] && ARCHIVED=${#BATCH_IDS[@]}
  fi
fi

jq -n \
  --arg profile "${PROFILE}" \
  --arg query "${QUERY_CMD}" \
  --argjson limit "${LIMIT}" \
  --argjson totalUnread "${TOTAL}" \
  --argjson triaged "${TRIAGED}" \
  --argjson needsDraft "${COUNT_DRAFT}" \
  --argjson needsReview "${COUNT_REVIEW}" \
  --argjson needsLabel "${COUNT_LABEL}" \
  --argjson shouldIgnore "${COUNT_IGNORE}" \
  --arg labelImportant "${LABEL_PREFIX}-Importante" \
  --arg labelAguardando "${LABEL_PREFIX}-Aguardando" \
  --arg labelBaixo "${LABEL_PREFIX}-BaixoValor" \
  --arg labelImportantId "${LABEL_IMPORTANT_ID}" \
  --arg labelAguardandoId "${LABEL_AGUARDANDO_ID}" \
  --arg labelBaixoId "${LABEL_BAIXO_ID}" \
  --argjson appliedImportant "${APPLIED_IMPORTANT}" \
  --argjson appliedAguardando "${APPLIED_AGUARDANDO}" \
  --argjson appliedBaixo "${APPLIED_BAIXO}" \
  --argjson markedRead "${MARKED_READ}" \
  --argjson draftsCreated "${DRAFTS_CREATED}" \
  --argjson archived "${ARCHIVED}" \
  --argjson labelsReused "${LABELS_REUSED}" \
  --argjson labelsCreated "${LABELS_CREATED}" \
  --argjson workflowSummary "${WORKFLOW_SUMMARY}" \
  --argjson evidences "${EVIDENCES}" \
  --argjson errors "${ERRORS}" \
  '{
    profile: $profile,
    query: $query,
    limit: $limit,
    totalUnread: $totalUnread,
    triaged: $triaged,
    counts: {
      draft: $needsDraft,
      review: $needsReview,
      label: $needsLabel,
      ignore: $shouldIgnore
    },
    labels: {
      important: { name: $labelImportant, id: $labelImportantId, applied: $appliedImportant },
      aguardando: { name: $labelAguardando, id: $labelAguardandoId, applied: $appliedAguardando },
      baixoValor: { name: $labelBaixo, id: $labelBaixoId, applied: $appliedBaixo }
    },
    markedRead: $markedRead,
    draftsCreated: $draftsCreated,
    archived: $archived,
    labelsReused: $labelsReused,
    labelsCreated: $labelsCreated,
    workflowSummary: $workflowSummary,
    evidences: $evidences,
    errors: $errors
  }'
