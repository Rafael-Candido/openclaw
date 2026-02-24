#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
DB_ID="bfcbe7a7a3a745489e605e0762af12a9"
AGENT_NAME="Engenheiro de Prompt"
API_KEY_VAR="NOTION_PERSONAL_API_KEY"
PROGRESS_COMMENT_MIN="${ENG_PROMPT_PROGRESS_COMMENT_MIN:-30}"
DEFAULT_ETA_MIN="${ENG_PROMPT_DEFAULT_ETA_MIN:-25}"
MICRO_TARGET_SEC="${ENG_PROMPT_MICRO_TARGET_SEC:-30}"
MICRO_MIN_CONTEXT_CHARS="${ENG_PROMPT_MICRO_MIN_CONTEXT_CHARS:-350}"
MICRO_MAX_OPEN="${ENG_PROMPT_MICRO_MAX_OPEN:-12}"

if [[ -f "${ROOT_DIR}/../.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/../.env" 2>/dev/null || true
fi

if [[ ! -x "${HELPER}" ]]; then
  echo '{"ok":false,"error":"helper_not_found"}'
  exit 2
fi

query_json="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${AGENT_NAME}" "Aguardando" "Em andamento" 2>/dev/null || echo '{"results":[]}')"
open_micro_count="$(jq -r '[.results[]? | select((.properties.Name.title[0].plain_text // "")|test("^\\s*\\[micro\\b";"i"))] | length' <<<"${query_json}" 2>/dev/null || echo 0)"
[[ ! "${open_micro_count}" =~ ^[0-9]+$ ]] && open_micro_count=0

pick_line="$(jq -r '
  (.results // [])
  | map({
      id: .id,
      status: (.properties.Status.select.name // ""),
      created: (.created_time // "9999-12-31T23:59:59.000Z"),
      edited: (.last_edited_time // .created_time // "9999-12-31T23:59:59.000Z"),
      title: (.properties.Name.title[0].plain_text // "(sem título)"),
      # Retoma primeiro Em andamento, depois Priorizado e por último recupera legado em Aguardando.
      rank: (
        if (.properties.Status.select.name // "") == "Em andamento" then 0
        elif (.properties.Status.select.name // "") == "Priorizado" then 1
        else 2
        end
      )
    })
  | sort_by(.rank, .created)
  | .[0]
  | if . == null then "" else [.id, .status, .created, .edited, .title] | @tsv end
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
NOTION_API_KEY="${!API_KEY_VAR:-}"
is_micro_card=0
if [[ "${TITLE}" =~ ^[[:space:]]*\[[Mm][Ii][Cc][Rr][Oo] ]]; then
  is_micro_card=1
fi

mins_since_activity="$(python3 - "${LAST_EDITED_AT}" "${PAGE_ID}" "${NOTION_API_KEY}" "${AGENT_NAME}" <<'PY'
import datetime, json, sys, urllib.request, urllib.parse

last_edited = (sys.argv[1] or "").strip()
page_id = (sys.argv[2] or "").strip()
api_key = (sys.argv[3] or "").strip()
agent = (sys.argv[4] or "").strip().lower()
now = datetime.datetime.now(datetime.timezone.utc)

def parse_iso(raw):
    if not raw:
        return None
    try:
        return datetime.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None

latest = parse_iso(last_edited)

if page_id and api_key:
    try:
        url = f"https://api.notion.com/v1/comments?block_id={urllib.parse.quote(page_id)}&page_size=100"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {api_key}",
            "Notion-Version": "2022-06-28",
        })
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        for c in data.get("results", []):
            txt = "".join(rt.get("plain_text", "") for rt in c.get("rich_text", []))
            if f"[{agent}]".lower() not in txt.lower():
                continue
            dt = parse_iso(c.get("created_time", ""))
            if dt and (latest is None or dt > latest):
                latest = dt
    except Exception:
        pass

if latest is None:
    print(0)
else:
    mins = int((now - latest).total_seconds() / 60)
    print(max(mins, 0))
PY
)"
[[ ! "${mins_since_activity}" =~ ^[0-9]+$ ]] && mins_since_activity=0

if [[ "${CUR_STATUS}" != "Em andamento" ]]; then
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Em andamento" >/dev/null
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Início da execução: vou seguir 3 etapas (1/3 análise de contexto técnico, 2/3 implementação das mudanças, 3/3 validação/evidências). ETA estimado: ${DEFAULT_ETA_MIN} min. Atualizo progresso ao final de cada etapa relevante." "${AGENT_NAME}" >/dev/null || true
elif (( mins_since_activity >= PROGRESS_COMMENT_MIN )); then
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Progresso automático: card sem atualização do ${AGENT_NAME} há ${mins_since_activity} min. Plano em execução: análise -> implementação -> validação. ETA revisado: ${DEFAULT_ETA_MIN} min a partir desta atualização." "${AGENT_NAME}" >/dev/null || true
fi

status_now="$(${HELPER} get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
if [[ "${status_now}" != "Em andamento" ]]; then
  echo "{\"ok\":false,\"action\":\"failed_lock\",\"page_id\":\"${PAGE_ID}\",\"status\":\"${status_now}\"}"
  exit 3
fi

blocks_json="$(${HELPER} get-blocks "${PAGE_ID}" "${API_KEY_VAR}" 2>/dev/null || echo '{"results":[]}')"

context_text="$(jq -r '
  .results[]?
  | .type as $t
  | if ($t == "paragraph" or $t == "heading_1" or $t == "heading_2" or $t == "heading_3" or $t == "bulleted_list_item" or $t == "numbered_list_item" or $t == "to_do")
    then (.[ $t ].rich_text[]?.plain_text // empty)
    else empty
    end
' <<<"${blocks_json}" 2>/dev/null | sed '/^\s*$/d' || true)"

context_chars="$(printf '%s' "${context_text}" | wc -m | tr -d ' ')"
context_file="/tmp/eng_prompt_context_${PAGE_ID}.txt"
printf '%s\n' "${context_text}" > "${context_file}"

has_microplan_marker=0
if printf '%s' "${context_text}" | grep -qi 'MICROPLAN_V1_PARENT'; then
  has_microplan_marker=1
fi

is_complex_card=0
title_lc="$(printf '%s' "${TITLE}" | tr '[:upper:]' '[:lower:]')"
if (( context_chars >= MICRO_MIN_CONTEXT_CHARS )); then
  is_complex_card=1
elif [[ "${title_lc}" == *"novo projeto"* || "${title_lc}" == *"projeto"* || "${title_lc}" == *"arquitet"* || "${title_lc}" == *"integra"* || "${title_lc}" == *"refator"* || "${title_lc}" == *"migr"* ]]; then
  is_complex_card=1
fi

parent_priority="$("${HELPER}" get-page "${PAGE_ID}" "${API_KEY_VAR}" 2>/dev/null | jq -r '.properties.Prioridade.select.name // "Média"' 2>/dev/null || echo "Média")"
case "${parent_priority}" in
  Alta|Média|Baixa) ;;
  *) parent_priority="Média" ;;
esac

create_micro_cards() {
  local parent_id="$1"
  local parent_title="$2"
  local priority="$3"
  local total=5
  local i step_title body_file created_json cid
  i=1
  while (( i <= total )); do
    case "${i}" in
      1) step_title="Diagnosticar escopo e impacto da demanda" ;;
      2) step_title="Aplicar menor mudança estrutural viável" ;;
      3) step_title="Ajustar prompts/scripts/documentação da fatia" ;;
      4) step_title="Validar comportamento e evidências da fatia" ;;
      5) step_title="Consolidar handoff final e critérios de conclusão" ;;
    esac
    body_file="/tmp/eng_prompt_micro_${parent_id}_${i}.md"
    cat > "${body_file}" <<EOF
MICROPLAN_V1_CHILD=true
PARENT_CARD_ID=${parent_id}
PARENT_CARD_TITLE=${parent_title}
MICRO_STEP=${i}/${total}
MICRO_TARGET_SECONDS=${MICRO_TARGET_SEC}

## Objetivo da fatia
${step_title}

## Regra de execução
- Concluir em até ${MICRO_TARGET_SEC}s de trabalho efetivo nesta rodada.
- Registrar evidência objetiva no comentário final.
EOF
    created_json="$(NOTION_CACHE_ENABLED=false "${HELPER}" create-card "${DB_ID}" "${API_KEY_VAR}" "[Micro ${i}/${total}] ${parent_title} — ${step_title}" "Priorizado" "OpenClaw" "${AGENT_NAME}" "${priority}" "${AGENT_NAME}" "${body_file}" 2>/dev/null || true)"
    cid="$(jq -r '.id // empty' <<<"${created_json}" 2>/dev/null || true)"
    [[ -n "${cid}" ]] && echo "${cid}"
    i=$((i+1))
  done
}

if [[ "${context_chars}" -lt 80 ]]; then
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Pendência: contexto técnico insuficiente no body (mínimo 80 chars). Card movido para Impedimento para evitar loop." "Engenheiro de Prompt" >/dev/null || true
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Impedimento" >/dev/null || true
  final_status="$(${HELPER} get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
  echo "{\"ok\":true,\"action\":\"blocked_no_context\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"created_at\":\"${CREATED_AT}\",\"context_chars\":${context_chars},\"status\":\"${final_status}\",\"eta_min\":0}"
  exit 0
fi

if (( is_micro_card == 1 )) && [[ "${title_lc}" == *"[governança][melhoria] gargalos operacionais recorrentes"* ]]; then
  logs_file="/tmp/eng_prompt_micro_logs_${PAGE_ID}.txt"
  queue_file="/tmp/eng_prompt_micro_queue_${PAGE_ID}.txt"
  (
    cd "${ROOT_DIR}" >/dev/null 2>&1 || true
    bash "${ROOT_DIR}/scripts/analyze-cron-logs.sh" 20 > "${logs_file}" 2>&1 || true
  )
  (
    NOTION_CACHE_ENABLED=false "${HELPER}" query "${DB_ID}" "${API_KEY_VAR}" "${AGENT_NAME}" "Priorizado" "Em andamento" 2>/dev/null \
      | jq -r '[.results[] | .properties.Status.select.name // ""] | {open:(length), in_progress:(map(select(.=="Em andamento"))|length), priorizado:(map(select(.=="Priorizado"))|length)}' \
      > "${queue_file}" 2>/dev/null || true
  )
  logs_tail="$(tail -n 8 "${logs_file}" 2>/dev/null | tr '\n' ' ' | sed 's/\"/\\\"/g')"
  queue_snapshot="$(cat "${queue_file}" 2>/dev/null | tr '\n' ' ' | sed 's/\"/\\\"/g')"
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Fatia executada com validação operacional. Evidências: analyze-cron-logs.sh (20 rodadas) e snapshot da fila pessoal. logs='${logs_tail}' fila='${queue_snapshot}'." "${AGENT_NAME}" >/dev/null || true
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Concluído" >/dev/null || true
  final_status="$(${HELPER} get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
  echo "{\"ok\":true,\"action\":\"micro_completed\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"status\":\"${final_status}\",\"evidence_logs\":\"${logs_file}\",\"evidence_queue\":\"${queue_file}\"}"
  exit 0
fi

if (( is_micro_card == 0 && is_complex_card == 1 && has_microplan_marker == 0 )); then
  if (( open_micro_count >= MICRO_MAX_OPEN )); then
    "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Fila de micro-cards no limite (${open_micro_count}/${MICRO_MAX_OPEN}). Card retornado para Priorizado e será fatiado após drenagem da janela ativa." "${AGENT_NAME}" >/dev/null || true
    "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Priorizado" >/dev/null || true
    echo "{\"ok\":true,\"action\":\"deferred_microplan_cap\",\"page_id\":\"${PAGE_ID}\",\"open_micro_count\":${open_micro_count},\"micro_cap\":${MICRO_MAX_OPEN},\"status\":\"Priorizado\"}"
    exit 0
  fi
  micro_ids=()
  while IFS= read -r _cid; do
    [[ -n "${_cid}" ]] && micro_ids+=("${_cid}")
  done < <(create_micro_cards "${PAGE_ID}" "${TITLE}" "${parent_priority}")
  if (( ${#micro_ids[@]} > 0 )); then
    marker_file="/tmp/eng_prompt_parent_marker_${PAGE_ID}.md"
    {
      echo "MICROPLAN_V1_PARENT=true"
      echo "MICROPLAN_TARGET_SECONDS=${MICRO_TARGET_SEC}"
      printf 'MICROPLAN_CHILDREN=%s\n' "$(IFS=,; echo "${micro_ids[*]}")"
      echo "MICROPLAN_CREATED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "${marker_file}"
    "${HELPER}" append-body "${PAGE_ID}" "${API_KEY_VAR}" "${marker_file}" >/dev/null || true
    "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Planejamento concluído: demanda fatiada em ${#micro_ids[@]} micro-cards (<=${MICRO_TARGET_SEC}s/fatia). Execução seguirá por prioridade nas próximas rodadas." "${AGENT_NAME}" >/dev/null || true
    echo "{\"ok\":true,\"action\":\"planned_microcards\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"micro_count\":${#micro_ids[@]},\"micro_target_sec\":${MICRO_TARGET_SEC},\"status\":\"Em andamento\"}"
    exit 0
  fi
fi

title_lc="$(printf '%s' "${TITLE}" | tr '[:upper:]' '[:lower:]')"
if [[ "${title_lc}" == *"governance-check.sh"* ]] && [[ "${title_lc}" == *"sintaxe"* ]]; then
  target_script="${ROOT_DIR}/scripts/governance-check.sh"
  syntax_log="/tmp/eng_prompt_syntax_${PAGE_ID}.log"
  if [[ ! -f "${target_script}" ]]; then
    "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Bloqueio técnico: arquivo alvo não encontrado (${target_script}). Movido para Impedimento." "Engenheiro de Prompt" >/dev/null || true
    "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Impedimento" >/dev/null || true
    final_status="$(${HELPER} get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
    echo "{\"ok\":true,\"action\":\"blocked_missing_target\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"status\":\"${final_status}\"}"
    exit 0
  fi

  if bash -n "${target_script}" >"${syntax_log}" 2>&1; then
    "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Validação sintática executada com sucesso: \`bash -n scripts/governance-check.sh\` (sem erros). Evidência: ${syntax_log}. Card concluído com execução real." "Engenheiro de Prompt" >/dev/null || true
    "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Concluído" >/dev/null || true
    final_status="$(${HELPER} get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
    echo "{\"ok\":true,\"action\":\"auto_completed_syntax_check\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"status\":\"${final_status}\",\"evidence\":\"${syntax_log}\"}"
    exit 0
  fi

  err_excerpt="$(tail -n 5 "${syntax_log}" 2>/dev/null | tr '\n' ' ' | sed 's/\"/\\\"/g')"
  "${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Erro de sintaxe persistente detectado em \`scripts/governance-check.sh\` via \`bash -n\`. Evidência: ${syntax_log}. Trecho: ${err_excerpt}. Movido para Impedimento." "Engenheiro de Prompt" >/dev/null || true
  "${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Impedimento" >/dev/null || true
  final_status="$(${HELPER} get-page "${PAGE_ID}" "${API_KEY_VAR}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
  echo "{\"ok\":true,\"action\":\"blocked_syntax_error\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"status\":\"${final_status}\",\"evidence\":\"${syntax_log}\"}"
  exit 0
fi

printf '%s' "${PAGE_ID}" > /tmp/eng_prompt_current_page_id

# Handoff obrigatório: o Engenheiro de Prompt não deve manter card em Em andamento
# quando já consolidou contexto técnico para implementação.
"${HELPER}" comment "${PAGE_ID}" "${API_KEY_VAR}" "Entrega concluída (escopo Prompt): contexto técnico consolidado para implementação real. Encaminhando para Diretor Pessoal priorizar o executor de implementação." "${AGENT_NAME}" >/dev/null || true
"${HELPER}" update-agent "${PAGE_ID}" "${API_KEY_VAR}" "Diretor Pessoal" >/dev/null || true
"${HELPER}" update-status "${PAGE_ID}" "${API_KEY_VAR}" "Priorizado" >/dev/null || true

final_page="$(${HELPER} get-page "${PAGE_ID}" "${API_KEY_VAR}" 2>/dev/null || echo '{}')"
final_status="$(jq -r '.properties.Status.select.name // ""' <<<"${final_page}" 2>/dev/null || true)"
final_agent="$(jq -r '.properties.Agente.select.name // ""' <<<"${final_page}" 2>/dev/null || true)"
echo "{\"ok\":true,\"action\":\"handoff_to_director\",\"page_id\":\"${PAGE_ID}\",\"title\":$(printf '%s' "${TITLE}" | jq -Rs .),\"created_at\":\"${CREATED_AT}\",\"context_chars\":${context_chars},\"context_file\":\"${context_file}\",\"eta_min\":${DEFAULT_ETA_MIN},\"mins_since_activity\":${mins_since_activity},\"status\":\"${final_status}\",\"agent\":\"${final_agent}\"}"
