#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
RUNTIME_GUARD="${SCRIPT_DIR}/runtime-guard.sh"
DB_ID="adec12e735dc41a3bb7c274b287f3a10"
API_KEY_VAR="NOTION_SMARTENVIOS_API_KEY"
DIRECTOR="Diretor Tech"

if [[ -f "${SCRIPT_DIR}/../../.env" ]]; then
  set +e +u
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../../.env" >/dev/null 2>&1
  set -euo pipefail
fi

if [[ -x "${RUNTIME_GUARD}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_GUARD}"
  if ! ocw_guard_acquire_lock "director-tech-deterministic" "${CRON_LOCK_STALE_SEC:-1200}"; then
    echo '{"ok":true,"action":"skipped_already_running","lock":"director-tech-deterministic"}'
    exit 0
  fi
  trap 'ocw_guard_release_lock' EXIT
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
      title: (.properties.Name.title[0].plain_text // "(sem título)"),
      rank: (if (.properties.Status.select.name // "") == "Em andamento" then 0 else 1 end)
    })
  | sort_by(.rank, .created)
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
REQUIRES_MICROPLAN=0

if [[ "$TITLE_LC" == *"mail"* || "$TITLE_LC" == *"email"* || "$TITLE_LC" == *"inbox"* || "$TITLE_LC" == *"triagem"* || "$TITLE_LC" == *"scoring"* ]]; then
  TARGET_AGENT="Mail-Pro"
  REASON="demanda de esteira de e-mail profissional"
fi

# Demandas de atendimento operacional de software ficam com o especialista dedicado.
if [[ "$TITLE_LC" == *"atendimento"* || "$TITLE_LC" == *"suporte"* || "$TITLE_LC" == *"ticket"* || "$TITLE_LC" == *"chamado"* || "$TITLE_LC" == *"central"* || "$TITLE_LC" == *"crm"* || "$TITLE_LC" == *"portal"* ]]; then
  TARGET_AGENT="Especialista de Suporte de Software"
  REASON="demanda operacional de suporte de software"
fi

# Demandas de automação/n8n devem ir para o especialista correto.
if [[ "$TITLE_LC" == *"n8n"* || "$TITLE_LC" == *"workflow"* || "$TITLE_LC" == *"automação"* || "$TITLE_LC" == *"automacao"* ]]; then
  TARGET_AGENT="Engenheiro de Automação"
  REASON="demanda de automação/n8n"
fi

# Demandas de infraestrutura de capability MCP são responsabilidade do Diretor Tech.
if [[ "$TITLE_LC" == *"mcp n8n"* || "$TITLE_LC" == *"habilitar escrita"* || "$TITLE_LC" == *"[infra]"* ]]; then
  TARGET_AGENT="Diretor Tech"
  REASON="demanda de infraestrutura/capability MCP"
fi

if [[ "$TITLE_LC" == *"novo projeto"* || "$TITLE_LC" == *"projeto"* || "$TITLE_LC" == *"arquitet"* || "$TITLE_LC" == *"integra"* || "$TITLE_LC" == *"refator"* || "$TITLE_LC" == *"migr"* ]]; then
  REQUIRES_MICROPLAN=1
fi

"${HELPER}" update-agent "${PAGE_ID}" "${API_KEY_VAR}" "${TARGET_AGENT}" >/dev/null || true
if (( REQUIRES_MICROPLAN == 1 )); then
  micro_file="/tmp/director_tech_microplan_${PAGE_ID}.md"
  cat > "${micro_file}" <<EOF
REQUIRES_MICROPLAN=true
MICROPLAN_TARGET_SECONDS=30
MICROPLAN_OWNER=${TARGET_AGENT}
MICROPLAN_REASON=escopo_complexo_detectado_na_triagem
EOF
  "${HELPER}" append-body "${PAGE_ID}" "${API_KEY_VAR}" "${micro_file}" >/dev/null || true
  rm -f "${micro_file}" 2>/dev/null || true
  MICRO_NOTE=" Próximo: execução individual com fatiamento em micro-cards (<=30s/fatia)."
else
  MICRO_NOTE=" Próximo: execução individual pelo especialista com evidências reais."
fi
"${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Triagem concluída: roteado para ${TARGET_AGENT} (${REASON}).${MICRO_NOTE}" "Diretor Tech" >/dev/null || true
"${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Priorizado" >/dev/null || true
final_page="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" 2>/dev/null || echo '{}')"
FINAL_STATUS="$(jq -r '.properties.Status.select.name // ""' <<<"${final_page}" 2>/dev/null || true)"
FINAL_AGENT="$(jq -r '.properties.Agente.select.name // ""' <<<"${final_page}" 2>/dev/null || true)"

echo "{\"ok\":true,\"action\":\"routed\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "$TITLE" | jq -Rs .),\"target_agent\":\"${TARGET_AGENT}\",\"final_status\":\"${FINAL_STATUS}\",\"final_agent\":\"${FINAL_AGENT}\"}"
