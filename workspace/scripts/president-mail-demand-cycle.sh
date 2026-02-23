#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
GMAIL="${ROOT_DIR}/scripts/gmail/gmail.sh"

if [[ -f "${ROOT_DIR}/../.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/../.env" 2>/dev/null || true
fi

if [[ ! -x "${HELPER}" || ! -x "${GMAIL}" ]]; then
  echo '{"ok":false,"error":"required_scripts_missing"}'
  exit 2
fi

TECH_DB="adec12e735dc41a3bb7c274b287f3a10"
PERSONAL_DB="bfcbe7a7a3a745489e605e0762af12a9"
CREATE_THRESHOLD_PRO="${MAIL_BACKLOG_CREATE_THRESHOLD_PRO:-20}"
CREATE_THRESHOLD_PERSONAL="${MAIL_BACKLOG_CREATE_THRESHOLD_PERSONAL:-5}"

[[ ! "${CREATE_THRESHOLD_PRO}" =~ ^[0-9]+$ ]] && CREATE_THRESHOLD_PRO=20
[[ ! "${CREATE_THRESHOLD_PERSONAL}" =~ ^[0-9]+$ ]] && CREATE_THRESHOLD_PERSONAL=5

unread_pro="$("${GMAIL}" pro list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
unread_personal="$("${GMAIL}" personal list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
[[ ! "${unread_pro}" =~ ^[0-9]+$ ]] && unread_pro=0
[[ ! "${unread_personal}" =~ ^[0-9]+$ ]] && unread_personal=0

query_agent_open() {
  local db_id="$1"
  local api_var="$2"
  local agent="$3"
  local q1 q2
  q1="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
  q2="$(NOTION_CACHE_ENABLED=false "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"
  jq -n --argjson a "${q1}" --argjson b "${q2}" '
    ((($a.results // []) + ($b.results // [])) | map(.id) | unique | length)
  '
}

active_director_tech="$(query_agent_open "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" 2>/dev/null || echo 0)"
active_director_personal="$(query_agent_open "${PERSONAL_DB}" NOTION_PERSONAL_API_KEY "Diretor Pessoal" 2>/dev/null || echo 0)"
[[ ! "${active_director_tech}" =~ ^[0-9]+$ ]] && active_director_tech=0
[[ ! "${active_director_personal}" =~ ^[0-9]+$ ]] && active_director_personal=0

created_pro=0
created_personal=0
created_cards='[]'

create_card_for_domain() {
  local db_id="$1"
  local api_var="$2"
  local title="$3"
  local agent="$4"
  local priority="$5"
  local body_file="$6"

  local created_json page_id
  created_json="$("${HELPER}" create-card "${db_id}" "${api_var}" "${title}" "Aguardando" "OpenClaw" "${agent}" "${priority}" "Presidente" "${body_file}" 2>/dev/null || true)"
  page_id="$(jq -r '.id // empty' <<<"${created_json}" 2>/dev/null || true)"
  if [[ -n "${page_id}" ]]; then
    created_cards="$(jq -cn --argjson arr "${created_cards}" --arg id "${page_id}" '$arr + [$id]')"
    return 0
  fi
  return 1
}

if (( unread_pro >= CREATE_THRESHOLD_PRO )) && (( active_director_tech == 0 )); then
  body="/tmp/president_mail_pro_body.txt"
  cat > "${body}" <<EOF
## Contexto
Backlog de e-mail profissional detectado com ${unread_pro} não lidos (is:unread in:inbox).

## Objetivo
Criar demanda operacional para Diretor Tech priorizar e encaminhar para Mail-Pro.

## Escopo
- Triar 1 card por rodada até zerar backlog.
- Garantir execução real por Mail-Pro com evidências (labels/arquivamento/rascunhos quando aplicável).

## Critério de sucesso
- Card priorizado para especialista e concluído com evidência objetiva.
- Redução progressiva dos não lidos.
EOF
  if create_card_for_domain "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "[Rotina Mail-Pro] Drenagem de backlog (${unread_pro} não lidos)" "Diretor Tech" "Alta" "${body}"; then
    created_pro=1
  fi
fi

if (( unread_personal >= CREATE_THRESHOLD_PERSONAL )) && (( active_director_personal == 0 )); then
  body="/tmp/president_mail_person_body.txt"
  cat > "${body}" <<EOF
## Contexto
Backlog de e-mail pessoal detectado com ${unread_personal} não lidos (is:unread in:inbox).

## Objetivo
Criar demanda operacional para Diretor Pessoal priorizar e encaminhar para Mail-Person.

## Escopo
- Triar 1 card por rodada até normalizar a caixa.
- Garantir execução real por Mail-Person com evidências.

## Critério de sucesso
- Card priorizado para especialista e concluído com evidência objetiva.
- Redução progressiva dos não lidos.
EOF
  if create_card_for_domain "${PERSONAL_DB}" NOTION_PERSONAL_API_KEY "[Rotina Mail-Person] Drenagem de backlog (${unread_personal} não lidos)" "Diretor Pessoal" "Alta" "${body}"; then
    created_personal=1
  fi
fi

echo "$(jq -cn \
  --argjson unreadPro "${unread_pro}" \
  --argjson unreadPersonal "${unread_personal}" \
  --argjson thresholdPro "${CREATE_THRESHOLD_PRO}" \
  --argjson thresholdPersonal "${CREATE_THRESHOLD_PERSONAL}" \
  --argjson activeDirectorTech "${active_director_tech}" \
  --argjson activeDirectorPersonal "${active_director_personal}" \
  --argjson createdPro "${created_pro}" \
  --argjson createdPersonal "${created_personal}" \
  --argjson cards "${created_cards}" \
  '{
    ok:true,
    action:"president_mail_backlog_guard",
    unreadPro:$unreadPro,
    unreadPersonal:$unreadPersonal,
    thresholdPro:$thresholdPro,
    thresholdPersonal:$thresholdPersonal,
    activeDirectorTech:$activeDirectorTech,
    activeDirectorPersonal:$activeDirectorPersonal,
    createdPro:$createdPro,
    createdPersonal:$createdPersonal,
    createdCards:$cards
  }')"
