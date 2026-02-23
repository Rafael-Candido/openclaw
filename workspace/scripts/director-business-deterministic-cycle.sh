#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
DB_ID="14abf9163c9680ff822bc2e32f6bec4b"
API_KEY_VAR="NOTION_CANPER_API_KEY"
DIRECTOR="Diretor Negócios"
TARGET_AGENT="Tech"

if [[ -f "${ROOT_DIR}/../.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/../.env" 2>/dev/null || true
fi

if [[ ! -x "${HELPER}" ]]; then
  echo '{"ok":false,"error":"helper_not_found"}'
  exit 2
fi

q_ag="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${DIRECTOR}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
q_run="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${DIRECTOR}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"

line="$(jq -r -n --argjson a "${q_ag}" --argjson b "${q_run}" '
  (($a.results // []) + ($b.results // []))
  | map({
      id: .id,
      created: (.created_time // "9999-12-31T23:59:59.000Z"),
      status: (.properties.Status.select.name // ""),
      title: (.properties.Name.title[0].plain_text // "(sem título)"),
      rank: (if (.properties.Status.select.name // "") == "Aguardando" then 0 else 1 end)
    })
  | sort_by(.rank, .created)
  | .[0]
  | if . == null then "" else [.id, .status, .title, .created] | @tsv end
')"

if [[ -z "${line}" ]]; then
  echo '{"ok":true,"action":"no_card"}'
  exit 0
fi

PAGE_ID="$(awk -F'\t' '{print $1}' <<<"${line}")"
CUR_STATUS="$(awk -F'\t' '{print $2}' <<<"${line}")"
TITLE="$(awk -F'\t' '{print $3}' <<<"${line}")"
CREATED_AT="$(awk -F'\t' '{print $4}' <<<"${line}")"

if [[ "${CUR_STATUS}" != "Em andamento" ]]; then
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Em andamento" >/dev/null || true
fi

"${HELPER}" update-agent "${PAGE_ID}" "${API_KEY_VAR}" "${TARGET_AGENT}" >/dev/null || true
"${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Triagem determinística concluída pelo Diretor Negócios. Card roteado para ${TARGET_AGENT} (1 card mais antigo da fila)." "${DIRECTOR}" >/dev/null || true
"${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Priorizado" >/dev/null || true

verify_status="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
verify_agent="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Agente.select.name // ""' 2>/dev/null || true)"

echo "{\"ok\":true,\"action\":\"routed\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"created_at\":\"${CREATED_AT}\",\"status\":\"${verify_status}\",\"agent\":\"${verify_agent}\"}"
