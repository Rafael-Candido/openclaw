#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
RUNTIME_GUARD="${SCRIPT_DIR}/runtime-guard.sh"
BACKOFFICE_HELPER="${ROOT_DIR}/agents/esp-suporte-software/scripts/support-backoffice-api.sh"
DB_ID="adec12e735dc41a3bb7c274b287f3a10"
AGENT_NAME="Especialista de Suporte de Software"
DIRECTOR_NAME="Diretor Tech"
API_KEY_VAR="NOTION_SMARTENVIOS_API_KEY"
PROGRESS_COMMENT_MIN="${SUP_SOFT_PROGRESS_COMMENT_MIN:-25}"
DEFAULT_ETA_MIN="${SUP_SOFT_DEFAULT_ETA_MIN:-20}"

if [[ -f "${ROOT_DIR}/../.env" ]]; then
  set +e +u
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/../.env" >/dev/null 2>&1
  set -euo pipefail
fi

if [[ -x "${RUNTIME_GUARD}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_GUARD}"
  if ! ocw_guard_acquire_lock "esp-suporte-software-deterministic" "${CRON_LOCK_STALE_SEC:-1200}"; then
    echo '{"ok":true,"action":"skipped_already_running","lock":"esp-suporte-software-deterministic"}'
    exit 0
  fi
  trap 'ocw_guard_release_lock' EXIT
fi

[[ -x "${HELPER}" ]] || { echo '{"ok":false,"error":"helper_not_found"}'; exit 2; }
[[ -x "${BACKOFFICE_HELPER}" ]] || { echo '{"ok":false,"error":"backoffice_helper_not_found"}'; exit 2; }

query_json="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${AGENT_NAME}" "Priorizado" "Em andamento" 2>/dev/null || echo '{"results":[]}')"

pick_line="$(jq -r '
  (.results // [])
  | map({
      id: .id,
      status: (.properties.Status.select.name // ""),
      created: (.created_time // "9999-12-31T23:59:59.000Z"),
      edited: (.last_edited_time // .created_time // "9999-12-31T23:59:59.000Z"),
      title: (.properties.Name.title[0].plain_text // "(sem título)"),
      rank: (if (.properties.Status.select.name // "") == "Em andamento" then 0 else 1 end)
    })
  | sort_by(.rank, .created)
  | .[0]
  | if . == null then "" else [.id,.status,.created,.edited,.title] | @tsv end
' <<<"${query_json}" 2>/dev/null || true)"

if [[ -z "${pick_line}" ]]; then
  echo '{"ok":true,"action":"no_card"}'
  exit 0
fi

PAGE_ID="$(awk -F'\t' '{print $1}' <<<"${pick_line}")"
CUR_STATUS="$(awk -F'\t' '{print $2}' <<<"${pick_line}")"
CREATED_AT="$(awk -F'\t' '{print $3}' <<<"${pick_line}")"
LAST_EDITED_AT="$(awk -F'\t' '{print $4}' <<<"${pick_line}")"
TITLE="$(awk -F'\t' '{print $5}' <<<"${pick_line}")"

mins_since_activity="$(python3 - "${LAST_EDITED_AT}" <<'PY'
import datetime
import sys

raw = (sys.argv[1] or "").strip()
try:
    dt = datetime.datetime.fromisoformat(raw.replace("Z", "+00:00"))
except Exception:
    print(0)
    raise SystemExit(0)

now = datetime.datetime.now(datetime.timezone.utc)
mins = int((now - dt).total_seconds() / 60)
print(max(mins, 0))
PY
)"
[[ ! "${mins_since_activity}" =~ ^[0-9]+$ ]] && mins_since_activity=0

if [[ "${CUR_STATUS}" != "Em andamento" ]]; then
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Em andamento" >/dev/null || true
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Início da execução: vou validar contexto e sinais operacionais em central/plataforma/CRM/Jira. ETA estimado: ${DEFAULT_ETA_MIN} min." "${AGENT_NAME}" >/dev/null || true
elif (( mins_since_activity >= PROGRESS_COMMENT_MIN )); then
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Progresso automático: card sem atualização há ${mins_since_activity} min. Continuo diagnóstico operacional com evidências (central/plataforma/CRM/Jira). ETA revisado: ${DEFAULT_ETA_MIN} min." "${AGENT_NAME}" >/dev/null || true
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

context_file="/tmp/esp_suporte_software_context_${PAGE_ID}.txt"
printf '%s\n' "${context_text}" > "${context_file}"

if [[ "${context_chars}" -lt 80 ]]; then
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Pendência: contexto técnico insuficiente no body (mínimo 80 chars). Card devolvido para ${DIRECTOR_NAME} detalhar escopo executável." "${AGENT_NAME}" >/dev/null || true
  "${HELPER}" update-agent "${PAGE_ID}" "${API_KEY_VAR}" "${DIRECTOR_NAME}" >/dev/null || true
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Priorizado" >/dev/null || true
  final_page="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" 2>/dev/null || echo '{}')"
  final_status="$(jq -r '.properties.Status.select.name // ""' <<<"${final_page}" 2>/dev/null || true)"
  final_agent="$(jq -r '.properties.Agente.select.name // ""' <<<"${final_page}" 2>/dev/null || true)"
  echo "{\"ok\":true,\"action\":\"needs_context_from_director\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"created_at\":\"${CREATED_AT}\",\"context_chars\":${context_chars},\"status\":\"${final_status}\",\"agent\":\"${final_agent}\"}"
  exit 0
fi

check_service() {
  local svc="$1"
  local r
  r="$("${BACKOFFICE_HELPER}" "${svc}" GET / 2>/dev/null || echo '{"ok":false,"http_status":0,"error":"request_failed"}')"
  local ok
  ok="$(jq -r '.ok // false' <<<"${r}" 2>/dev/null || echo false)"
  if [[ "${ok}" != "true" ]]; then
    r="$("${BACKOFFICE_HELPER}" "${svc}" GET /health 2>/dev/null || echo '{"ok":false,"http_status":0,"error":"request_failed"}')"
  fi
  printf '%s' "${r}"
}

platform_check="$(check_service plataform)"
central_check="$(check_service central)"
crm_check="$(check_service crm)"

platform_status="$(jq -r '.http_status // 0' <<<"${platform_check}" 2>/dev/null || echo 0)"
central_status="$(jq -r '.http_status // 0' <<<"${central_check}" 2>/dev/null || echo 0)"
crm_status="$(jq -r '.http_status // 0' <<<"${crm_check}" 2>/dev/null || echo 0)"

if [[ "${CUR_STATUS}" != "Em andamento" ]]; then
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Snapshot inicial de conectividade: plataforma=${platform_status}, central=${central_status}, crm=${crm_status}. Próximo passo: consolidar causa provável e plano de ação no card/Jira." "${AGENT_NAME}" >/dev/null || true
fi

echo "$(jq -n \
  --arg page_id "${PAGE_ID}" \
  --arg title "${TITLE}" \
  --arg created_at "${CREATED_AT}" \
  --arg context_file "${context_file}" \
  --argjson context_chars "${context_chars}" \
  --argjson mins_since_activity "${mins_since_activity}" \
  --argjson platform "${platform_check}" \
  --argjson central "${central_check}" \
  --argjson crm "${crm_check}" \
  '{
    ok: true,
    action: "support_triage_ready",
    page_id: $page_id,
    title: $title,
    created_at: $created_at,
    context_chars: $context_chars,
    context_file: $context_file,
    mins_since_activity: $mins_since_activity,
    checks: {
      plataform: $platform,
      central: $central,
      crm: $crm
    }
  }')"
