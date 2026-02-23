#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
DB_ID="adec12e735dc41a3bb7c274b287f3a10"
API_KEY_VAR="NOTION_SMARTENVIOS_API_KEY"
DIRECTOR="Diretor Tech"

if [[ -f "${SCRIPT_DIR}/../../.env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../../.env" 2>/dev/null || true
fi

[[ -x "${HELPER}" ]] || { echo '{"ok":false,"error":"helper_not_found"}'; exit 2; }

q_ag="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${DIRECTOR}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
q_run="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${DIRECTOR}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"

pick="$(jq -r -n --argjson a "$q_ag" --argjson r "$q_run" '
  (($a.results // []) + ($r.results // []))
  | map({
      id: .id,
      status: (.properties.Status.select.name // ""),
      created: (.created_time // "9999-12-31T23:59:59.000Z"),
      title: (.properties.Name.title[0].plain_text // "(sem título)")
    })
  | sort_by(.created)
  | .[0]
  | if . == null then "" else [.id,.status,.created,.title] | @tsv end
' 2>/dev/null || true)"

if [[ -z "${pick}" ]]; then
  echo '{"ok":true,"action":"no_card"}'
  exit 0
fi

PAGE_ID="$(awk -F'\t' '{print $1}' <<<"$pick")"
STATUS="$(awk -F'\t' '{print $2}' <<<"$pick")"
TITLE="$(awk -F'\t' '{print $4}' <<<"$pick")"

"${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Em andamento" >/dev/null || true

# Regras de roteamento do Diretor Tech (execução por especialista)
TITLE_LC="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]')"
TARGET_AGENT="Engenheiro SmartEnvios"
REASON="roteamento padrão tech"

if [[ "$TITLE_LC" == *"mail"* || "$TITLE_LC" == *"email"* || "$TITLE_LC" == *"inbox"* || "$TITLE_LC" == *"triagem"* || "$TITLE_LC" == *"scoring"* ]]; then
  TARGET_AGENT="Mail-Pro"
  REASON="demanda de esteira de e-mail profissional"
fi

"${HELPER}" update-agent "${PAGE_ID}" "${API_KEY_VAR}" "${TARGET_AGENT}" >/dev/null || true
"${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Triagem concluída: roteado para ${TARGET_AGENT} (${REASON}). Próximo: execução individual pelo especialista com evidências reais." "Diretor Tech" >/dev/null || true
"${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Priorizado" >/dev/null || true
FINAL_STATUS="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
FINAL_AGENT="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Agente.select.name // ""' 2>/dev/null || true)"

echo "{\"ok\":true,\"action\":\"routed\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "$TITLE" | jq -Rs .),\"target_agent\":\"${TARGET_AGENT}\",\"final_status\":\"${FINAL_STATUS}\",\"final_agent\":\"${FINAL_AGENT}\"}"
