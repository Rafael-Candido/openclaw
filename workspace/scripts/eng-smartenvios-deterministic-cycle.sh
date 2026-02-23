#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
DB_ID="adec12e735dc41a3bb7c274b287f3a10"
AGENT_NAME="Engenheiro SmartEnvios"
API_KEY_VAR="NOTION_SMARTENVIOS_API_KEY"

if [[ -f "${ROOT_DIR}/../.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/../.env" 2>/dev/null || true
fi

if [[ ! -x "${HELPER}" ]]; then
  echo '{"ok":false,"error":"helper_not_found"}'
  exit 2
fi

query_json="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${AGENT_NAME}" "Priorizado" "Em andamento" 2>/dev/null || echo '{"results":[]}')"

pick_line="$(jq -r '
  (.results // [])
  | map({
      id: .id,
      status: (.properties.Status.select.name // ""),
      created: (.created_time // "9999-12-31T23:59:59.000Z"),
      title: (.properties.Name.title[0].plain_text // "(sem título)"),
      rank: (if (.properties.Status.select.name // "") == "Priorizado" then 0 else 1 end)
    })
  | sort_by(.rank, .created)
  | .[0]
  | if . == null then "" else [.id, .status, .created, .title] | @tsv end
' <<<"${query_json}" 2>/dev/null || true)"

if [[ -z "${pick_line}" ]]; then
  echo '{"ok":true,"action":"no_card"}'
  exit 0
fi

PAGE_ID="$(awk -F'\t' '{print $1}' <<<"${pick_line}")"
CUR_STATUS="$(awk -F'\t' '{print $2}' <<<"${pick_line}")"
CREATED_AT="$(awk -F'\t' '{print $3}' <<<"${pick_line}")"
TITLE="$(awk -F'\t' '{print $4}' <<<"${pick_line}")"

if [[ "${CUR_STATUS}" != "Em andamento" ]]; then
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Em andamento" >/dev/null || true
fi

status_now="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
if [[ "${status_now}" != "Em andamento" ]]; then
  echo "{\"ok\":false,\"action\":\"failed_lock\",\"page_id\":\"${PAGE_ID}\",\"status\":\"${status_now}\"}"
  exit 3
fi

blocks_json="$("${HELPER}" get-blocks "${PAGE_ID}" "${API_KEY_VAR}" 2>/dev/null || echo '{"results":[]}')"
context_text="$(jq -r '
  .results[]?
  | .type as $t
  | if ($t == "paragraph" or $t == "heading_1" or $t == "heading_2" or $t == "heading_3" or $t == "bulleted_list_item" or $t == "numbered_list_item" or $t == "to_do")
    then (.[ $t ].rich_text[]?.plain_text // empty)
    else empty
    end
' <<<"${blocks_json}" 2>/dev/null | sed '/^\s*$/d' || true)"

context_chars="$(printf '%s' "${context_text}" | wc -m | tr -d ' ')"
context_file="/tmp/eng_smartenvios_context_${PAGE_ID}.txt"
printf '%s\n' "${context_text}" > "${context_file}"

if [[ "${context_chars}" -lt 80 ]]; then
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Pendência: contexto técnico insuficiente no body (mínimo 80 chars). Card movido para Impedimento para evitar loop." "Engenheiro SmartEnvios" >/dev/null || true
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Impedimento" >/dev/null || true
  final_status="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
  echo "{\"ok\":true,\"action\":\"blocked_no_context\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"created_at\":\"${CREATED_AT}\",\"context_chars\":${context_chars},\"status\":\"${final_status}\"}"
  exit 0
fi

echo "{\"ok\":true,\"action\":\"ready_for_implementation\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"created_at\":\"${CREATED_AT}\",\"context_chars\":${context_chars},\"context_file\":\"${context_file}\"}"
