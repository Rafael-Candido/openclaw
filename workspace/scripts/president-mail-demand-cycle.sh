#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
GMAIL="${ROOT_DIR}/scripts/gmail/gmail.sh"
OPENCLAW_HELPER="${SCRIPT_DIR}/openclaw-helper.sh"

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
CREATE_THRESHOLD_PRO="${MAIL_BACKLOG_CREATE_THRESHOLD_PRO:-1}"
CREATE_THRESHOLD_PERSONAL="${MAIL_BACKLOG_CREATE_THRESHOLD_PERSONAL:-1}"
COOLDOWN_SEC="${MAIL_BACKLOG_CREATE_COOLDOWN_SEC:-3600}"
STATE_FILE="/tmp/openclaw-president-mail-demand-state.json"
FORCE_FILE="/tmp/openclaw-president-force-governance.json"
FORCE_WAKE_STATE_FILE="/tmp/openclaw-president-force-wake-state.json"
FORCE_WAKE_COOLDOWN_SEC="${PRESIDENT_FORCE_WAKE_COOLDOWN_SEC:-600}"
PRESIDENT_DIRECT_WAKE_ENABLED="${PRESIDENT_DIRECT_WAKE_ENABLED:-false}"
FORCE_CHAIN_THRESHOLD_PRO="${PRESIDENT_FORCE_CHAIN_THRESHOLD_PRO:-20}"
FORCE_CHAIN_THRESHOLD_PERSONAL="${PRESIDENT_FORCE_CHAIN_THRESHOLD_PERSONAL:-5}"
FORCE_CHAIN_ENABLED="${PRESIDENT_FORCE_CHAIN_ENABLED:-true}"
CREATE_WHEN_CHAIN_EMPTY="${MAIL_BACKLOG_CREATE_WHEN_CHAIN_EMPTY:-true}"
GOVERNANCE_CRON_ID="${GOVERNANCE_CRON_ID:-}"
DIRECTOR_TECH_CRON="7fba5b1f-2ee9-4b1e-aae0-bd211c32b925"
DIRECTOR_PERSONAL_CRON="a71c2958-e52f-4f37-9876-bedf6dcb9434"
MAIL_PRO_CRON="99de71d1-97b0-48d0-933e-7fcacfda2184"
MAIL_PERSON_CRON="e4cd9635-efdd-4588-8ecc-523a4a50ea20"
OPTIMIZER_CRON="59c24991-af6c-4df2-95fe-bbf012cd73c0"

[[ ! "${CREATE_THRESHOLD_PRO}" =~ ^[0-9]+$ ]] && CREATE_THRESHOLD_PRO=1
[[ ! "${CREATE_THRESHOLD_PERSONAL}" =~ ^[0-9]+$ ]] && CREATE_THRESHOLD_PERSONAL=1
[[ ! "${COOLDOWN_SEC}" =~ ^[0-9]+$ ]] && COOLDOWN_SEC=3600
[[ ! "${FORCE_CHAIN_THRESHOLD_PRO}" =~ ^[0-9]+$ ]] && FORCE_CHAIN_THRESHOLD_PRO=20
[[ ! "${FORCE_CHAIN_THRESHOLD_PERSONAL}" =~ ^[0-9]+$ ]] && FORCE_CHAIN_THRESHOLD_PERSONAL=5
[[ ! "${FORCE_WAKE_COOLDOWN_SEC}" =~ ^[0-9]+$ ]] && FORCE_WAKE_COOLDOWN_SEC=600

force_chain_triggered=0
forced_crons='[]'

if [[ -f "${OPENCLAW_HELPER}" ]]; then
  # shellcheck disable=SC1091
  source "${OPENCLAW_HELPER}" 2>/dev/null || true
fi

unread_pro_file="/tmp/president-unread-pro-$$.txt"
unread_personal_file="/tmp/president-unread-personal-$$.txt"
"${GMAIL}" pro list "is:unread in:inbox" 1 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null >"${unread_pro_file}" &
pid_unread_pro=$!
"${GMAIL}" personal list "is:unread in:inbox" 1 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null >"${unread_personal_file}" &
pid_unread_personal=$!
wait "${pid_unread_pro}" "${pid_unread_personal}" 2>/dev/null || true
unread_pro="$(cat "${unread_pro_file}" 2>/dev/null || echo 0)"
unread_personal="$(cat "${unread_personal_file}" 2>/dev/null || echo 0)"
rm -f "${unread_pro_file}" "${unread_personal_file}" 2>/dev/null || true
[[ ! "${unread_pro}" =~ ^[0-9]+$ ]] && unread_pro=0
[[ ! "${unread_personal}" =~ ^[0-9]+$ ]] && unread_personal=0

query_agent_open() {
  local db_id="$1"
  local api_var="$2"
  local agent="$3"
  local q1 q2
  q1="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
  q2="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"
  jq -n --argjson a "${q1}" --argjson b "${q2}" '
    ((($a.results // []) + ($b.results // [])) | map(.id) | unique | length)
  '
}

query_agent_open_pages() {
  local db_id="$1"
  local api_var="$2"
  local agent="$3"
  local q1 q2
  q1="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
  q2="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"
  jq -n --argjson a "${q1}" --argjson b "${q2}" '
    ((($a.results // []) + ($b.results // [])) | unique_by(.id))
  '
}

count_chain_open_by_title_prefix() {
  local db_id="$1"
  local api_var="$2"
  local title_prefix="$3"
  local q_dir q_pres q_spec

  # Evita duplicação contando apenas cards da cadeia principal com o mesmo prefixo de título.
  if [[ "${db_id}" == "${TECH_DB}" ]]; then
    q_dir="$(query_agent_open_pages "${db_id}" "${api_var}" "Diretor Tech" 2>/dev/null || echo '[]')"
    q_pres="$(query_agent_open_pages "${db_id}" "${api_var}" "Presidente" 2>/dev/null || echo '[]')"
    q_spec="$(query_agent_open_pages "${db_id}" "${api_var}" "Mail-Pro" 2>/dev/null || echo '[]')"
  else
    q_dir="$(query_agent_open_pages "${db_id}" "${api_var}" "Diretor Pessoal" 2>/dev/null || echo '[]')"
    q_pres="$(query_agent_open_pages "${db_id}" "${api_var}" "Presidente" 2>/dev/null || echo '[]')"
    q_spec="$(query_agent_open_pages "${db_id}" "${api_var}" "Mail-Person" 2>/dev/null || echo '[]')"
  fi

  jq -n --argjson d "${q_dir:-[]}" --argjson p "${q_pres:-[]}" --argjson s "${q_spec:-[]}" --arg pref "${title_prefix}" '
    (($d + $p + $s)
      | map(select(((.properties.Name.title[0].plain_text // "") | startswith($pref))))
      | map(.id)
      | unique
      | length)
  '
}

can_create_with_cooldown() {
  local key="$1"
  local now last_created
  now="$(date +%s)"
  last_created=0
  if [[ -f "${STATE_FILE}" ]]; then
    last_created="$(jq -r --arg k "${key}" '.[$k] // 0' "${STATE_FILE}" 2>/dev/null || echo 0)"
  fi
  [[ ! "${last_created}" =~ ^[0-9]+$ ]] && last_created=0
  if (( now - last_created < COOLDOWN_SEC )); then
    return 1
  fi
  return 0
}

mark_created_now() {
  local key="$1"
  local now tmp
  now="$(date +%s)"
  tmp="${STATE_FILE}.tmp"
  if [[ -f "${STATE_FILE}" ]]; then
    jq --arg k "${key}" --argjson now "${now}" '.[$k]=$now' "${STATE_FILE}" > "${tmp}" 2>/dev/null || jq -n --arg k "${key}" --argjson now "${now}" '{($k):$now}' > "${tmp}"
  else
    jq -n --arg k "${key}" --argjson now "${now}" '{($k):$now}' > "${tmp}"
  fi
  mv "${tmp}" "${STATE_FILE}" 2>/dev/null || true
}

can_force_wake_now() {
  local now last
  now="$(date +%s)"
  last=0
  if [[ -f "${FORCE_WAKE_STATE_FILE}" ]]; then
    last="$(jq -r '.last // 0' "${FORCE_WAKE_STATE_FILE}" 2>/dev/null || echo 0)"
  fi
  [[ ! "${last}" =~ ^[0-9]+$ ]] && last=0
  (( now - last >= FORCE_WAKE_COOLDOWN_SEC ))
}

mark_force_wake_now() {
  local now tmp
  now="$(date +%s)"
  tmp="${FORCE_WAKE_STATE_FILE}.tmp"
  jq -n --argjson last "${now}" '{last:$last}' > "${tmp}" 2>/dev/null && mv "${tmp}" "${FORCE_WAKE_STATE_FILE}" 2>/dev/null || true
}

force_cron_once() {
  local cron_id="$1"
  [[ -z "${cron_id:-}" ]] && return 0
  if command -v ocw_cron_wake_now >/dev/null 2>&1; then
    if ocw_cron_wake_now "${cron_id}" 6000 >/dev/null 2>&1 || ocw_cron_run "${cron_id}" 6000 >/dev/null 2>&1; then
      forced_crons="$(jq -cn --argjson arr "${forced_crons}" --arg id "${cron_id}" '$arr + [$id]')"
      return 0
    fi
  fi
  if openclaw cron edit "${cron_id}" --wake now --timeout 6000 >/dev/null 2>&1 || openclaw cron run "${cron_id}" --timeout 6000 >/dev/null 2>&1; then
    forced_crons="$(jq -cn --argjson arr "${forced_crons}" --arg id "${cron_id}" '$arr + [$id]')"
    return 0
  fi
  return 1
}

active_director_tech_file="/tmp/president-active-tech-$$.txt"
active_director_personal_file="/tmp/president-active-personal-$$.txt"
active_chain_tech_file="/tmp/president-chain-tech-$$.txt"
active_chain_personal_file="/tmp/president-chain-personal-$$.txt"

query_agent_open "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" 2>/dev/null >"${active_director_tech_file}" &
pid_active_tech=$!
query_agent_open "${PERSONAL_DB}" NOTION_PERSONAL_API_KEY "Diretor Pessoal" 2>/dev/null >"${active_director_personal_file}" &
pid_active_personal=$!
count_chain_open_by_title_prefix "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "[Rotina Mail-Pro]" 2>/dev/null >"${active_chain_tech_file}" &
pid_chain_tech=$!
count_chain_open_by_title_prefix "${PERSONAL_DB}" NOTION_PERSONAL_API_KEY "[Rotina Mail-Person]" 2>/dev/null >"${active_chain_personal_file}" &
pid_chain_personal=$!

wait "${pid_active_tech}" "${pid_active_personal}" "${pid_chain_tech}" "${pid_chain_personal}" 2>/dev/null || true

active_director_tech="$(cat "${active_director_tech_file}" 2>/dev/null || echo 0)"
active_director_personal="$(cat "${active_director_personal_file}" 2>/dev/null || echo 0)"
[[ ! "${active_director_tech}" =~ ^[0-9]+$ ]] && active_director_tech=0
[[ ! "${active_director_personal}" =~ ^[0-9]+$ ]] && active_director_personal=0
active_chain_tech="$(cat "${active_chain_tech_file}" 2>/dev/null || echo 0)"
active_chain_personal="$(cat "${active_chain_personal_file}" 2>/dev/null || echo 0)"
[[ ! "${active_chain_tech}" =~ ^[0-9]+$ ]] && active_chain_tech=0
[[ ! "${active_chain_personal}" =~ ^[0-9]+$ ]] && active_chain_personal=0
rm -f "${active_director_tech_file}" "${active_director_personal_file}" "${active_chain_tech_file}" "${active_chain_personal_file}" 2>/dev/null || true

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
  created_json="$(NOTION_CACHE_ENABLED=true "${HELPER}" create-card "${db_id}" "${api_var}" "${title}" "Aguardando" "OpenClaw" "${agent}" "${priority}" "Presidente" "${body_file}" 2>/dev/null || true)"
  page_id="$(jq -r '.id // empty' <<<"${created_json}" 2>/dev/null || true)"
  if [[ -n "${page_id}" ]]; then
    created_cards="$(jq -cn --argjson arr "${created_cards}" --arg id "${page_id}" '$arr + [$id]')"
    return 0
  fi
  return 1
}

should_create_pro=0
if (( unread_pro >= CREATE_THRESHOLD_PRO )) && (( active_chain_tech == 0 )); then
  if can_create_with_cooldown "pro"; then
    should_create_pro=1
  elif [[ "${CREATE_WHEN_CHAIN_EMPTY}" == "true" ]]; then
    should_create_pro=1
  fi
fi

if (( should_create_pro == 1 )); then
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
    mark_created_now "pro"
  fi
fi

should_create_personal=0
if (( unread_personal >= CREATE_THRESHOLD_PERSONAL )) && (( active_chain_personal == 0 )); then
  if can_create_with_cooldown "personal"; then
    should_create_personal=1
  elif [[ "${CREATE_WHEN_CHAIN_EMPTY}" == "true" ]]; then
    should_create_personal=1
  fi
fi

if (( should_create_personal == 1 )); then
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
    mark_created_now "personal"
  fi
fi

if [[ "${FORCE_CHAIN_ENABLED}" == "true" ]] && { (( unread_pro >= FORCE_CHAIN_THRESHOLD_PRO )) || (( unread_personal >= FORCE_CHAIN_THRESHOLD_PERSONAL )); }; then
  force_chain_triggered=1

  jq -n \
    --argjson unreadPro "${unread_pro}" \
    --argjson unreadPersonal "${unread_personal}" \
    --argjson thresholdPro "${FORCE_CHAIN_THRESHOLD_PRO}" \
    --argjson thresholdPersonal "${FORCE_CHAIN_THRESHOLD_PERSONAL}" \
    --arg reason "backlog_above_threshold" \
    --argjson createdPro "${created_pro}" \
    --argjson createdPersonal "${created_personal}" \
    --argjson at "$(date +%s)" \
    '{
      reason:$reason,
      unreadPro:$unreadPro,
      unreadPersonal:$unreadPersonal,
      thresholdPro:$thresholdPro,
      thresholdPersonal:$thresholdPersonal,
      createdPro:$createdPro,
      createdPersonal:$createdPersonal,
      requestedAt:$at
    }' > "${FORCE_FILE}.tmp" 2>/dev/null && mv "${FORCE_FILE}.tmp" "${FORCE_FILE}" 2>/dev/null || true

  if [[ "${PRESIDENT_DIRECT_WAKE_ENABLED}" == "true" ]] && can_force_wake_now; then
    # Evita sobreposição: acorda apenas a cadeia necessária por domínio.
    if (( unread_pro >= FORCE_CHAIN_THRESHOLD_PRO )) && { (( created_pro == 1 )) || (( active_chain_tech > 0 )); }; then
      force_cron_once "${DIRECTOR_TECH_CRON}" || true
      force_cron_once "${MAIL_PRO_CRON}" || true
    fi
    if (( unread_personal >= FORCE_CHAIN_THRESHOLD_PERSONAL )) && { (( created_personal == 1 )) || (( active_chain_personal > 0 )); }; then
      force_cron_once "${DIRECTOR_PERSONAL_CRON}" || true
      force_cron_once "${MAIL_PERSON_CRON}" || true
    fi
    if (( created_pro == 1 || created_personal == 1 )); then
      force_cron_once "${OPTIMIZER_CRON}" || true
    fi
    if [[ -n "${GOVERNANCE_CRON_ID}" ]]; then
      force_cron_once "${GOVERNANCE_CRON_ID}" || true
    fi
    mark_force_wake_now
  fi
fi

echo "$(jq -cn \
  --argjson unreadPro "${unread_pro}" \
  --argjson unreadPersonal "${unread_personal}" \
  --argjson thresholdPro "${CREATE_THRESHOLD_PRO}" \
  --argjson thresholdPersonal "${CREATE_THRESHOLD_PERSONAL}" \
  --argjson activeDirectorTech "${active_director_tech}" \
  --argjson activeDirectorPersonal "${active_director_personal}" \
  --argjson activeChainTech "${active_chain_tech}" \
  --argjson activeChainPersonal "${active_chain_personal}" \
  --argjson createdPro "${created_pro}" \
  --argjson createdPersonal "${created_personal}" \
  --argjson forceChainTriggered "${force_chain_triggered}" \
  --argjson forcedCrons "${forced_crons}" \
  --argjson cards "${created_cards}" \
  --arg directWake "${PRESIDENT_DIRECT_WAKE_ENABLED}" \
  '{
    ok:true,
    action:"president_mail_backlog_guard",
    unreadPro:$unreadPro,
    unreadPersonal:$unreadPersonal,
    thresholdPro:$thresholdPro,
    thresholdPersonal:$thresholdPersonal,
    activeDirectorTech:$activeDirectorTech,
    activeDirectorPersonal:$activeDirectorPersonal,
    activeChainTech:$activeChainTech,
    activeChainPersonal:$activeChainPersonal,
    createdPro:$createdPro,
    createdPersonal:$createdPersonal,
    forceChainTriggered:$forceChainTriggered,
    presidentDirectWakeEnabled:$directWake,
    forcedCrons:$forcedCrons,
    createdCards:$cards
  }')"
