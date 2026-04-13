#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_CONFIG_DIR:-/private/var/www/openclaw}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="$ROOT/workspace/reports"
TMP_DIR="$ROOT/workspace/tmp"
HYGIENE_SCRIPT="${SCRIPT_DIR}/openclaw-hygiene.sh"
mkdir -p "$REPORT_DIR" "$TMP_DIR"

if [[ -x "${HYGIENE_SCRIPT}" ]]; then
  "${HYGIENE_SCRIPT}" --apply --json --once-daily >/dev/null 2>&1 || true
fi

RUNTIME_GUARD="$SCRIPT_DIR/runtime-guard.sh"
if [[ -x "$RUNTIME_GUARD" ]]; then
  # shellcheck disable=SC1090
  source "$RUNTIME_GUARD"
  if ! ocw_guard_acquire_lock "codex-stability-cycle" "1800"; then
    echo '{"ok":true,"action":"skipped_already_running","lock":"codex-stability-cycle"}'
    exit 0
  fi
  trap 'ocw_guard_release_lock' EXIT
fi

TS="$(date -u +%Y%m%d-%H%M%S)"
REPORT_MD="$REPORT_DIR/stability-cycle-$TS.md"
REPORT_JSON="$REPORT_DIR/stability-cycle-$TS.json"

# Prefer timeout when available
TIMEOUT_CMD=""
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"; fi
if [[ -z "$TIMEOUT_CMD" ]] && command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"; fi

run_timed() {
  local sec="$1"; shift
  if [[ -n "$TIMEOUT_CMD" ]]; then
    "$TIMEOUT_CMD" "${sec}"s "$@"
  else
    "$@"
  fi
}

GATEWAY_OK=false
GATEWAY_RAW=""
if GATEWAY_RAW="$(run_timed 10 openclaw gateway health 2>&1)"; then
  GATEWAY_OK=true
fi

CRON_JSON="$(run_timed 15 openclaw cron list --json 2>/dev/null || echo '{"jobs":[]}')"

# Probes operacionais (mail/cards): detecta falso "ok" com backlog travado.
MAIL_PRO_RAW="$(run_timed 120 bash "$SCRIPT_DIR/gmail/process-notion-cards.sh" pro 15 2>/dev/null || echo '{}')"
MAIL_PERSON_RAW="$(run_timed 120 bash "$SCRIPT_DIR/gmail/process-notion-cards.sh" personal 15 2>/dev/null || echo '{}')"

mail_json_get() {
  local json="$1"
  local expr="$2"
  jq -r "${expr} // empty" <<<"${json}" 2>/dev/null || true
}

MAIL_PRO_BACKLOG="$(mail_json_get "${MAIL_PRO_RAW}" '.backlogEstimate')"
MAIL_PRO_CARDS="$(mail_json_get "${MAIL_PRO_RAW}" '.cardsFound')"
MAIL_PRO_MSG="$(mail_json_get "${MAIL_PRO_RAW}" '.message')"
MAIL_PERSON_BACKLOG="$(mail_json_get "${MAIL_PERSON_RAW}" '.backlogEstimate')"
MAIL_PERSON_CARDS="$(mail_json_get "${MAIL_PERSON_RAW}" '.cardsFound')"
MAIL_PERSON_MSG="$(mail_json_get "${MAIL_PERSON_RAW}" '.message')"

is_num() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
MAIL_STUCK=false
MAIL_STUCK_REASON=""
if is_num "${MAIL_PERSON_BACKLOG}" && is_num "${MAIL_PERSON_CARDS}"; then
  if (( MAIL_PERSON_BACKLOG > 0 )) && (( MAIL_PERSON_CARDS == 0 )); then
    MAIL_STUCK=true
    MAIL_STUCK_REASON="personal_backlog_without_card"
  fi
fi
if [[ "${MAIL_STUCK}" != "true" ]] && is_num "${MAIL_PRO_BACKLOG}" && is_num "${MAIL_PRO_CARDS}"; then
  if (( MAIL_PRO_BACKLOG > 0 )) && (( MAIL_PRO_CARDS == 0 )); then
    MAIL_STUCK=true
    MAIL_STUCK_REASON="pro_backlog_without_card"
  fi
fi

# Probes de acúmulo de cards (Notion): detecta fila crescente mesmo com crons "ok".
HELPER="$SCRIPT_DIR/notion-helper.sh"
PDB_ID="bfcbe7a7a3a745489e605e0762af12a9"
SDB_ID="adec12e735dc41a3bb7c274b287f3a10"
QUEUE_ALERT_THRESHOLD="${QUEUE_ALERT_THRESHOLD:-4}"

query_count() {
  local db="$1" key="$2" agent="$3" s1="$4" s2="$5"
  NOTION_CACHE_ENABLED=false run_timed 30 bash "$HELPER" query "$db" "$key" "$agent" "$s1" "$s2" 2>/dev/null \
    | jq -r '.results|length' 2>/dev/null || echo 0
}

P_DIR_Q="$(query_count "$PDB_ID" "NOTION_PERSONAL_API_KEY" "Diretor Pessoal" "Aguardando" "Priorizado")"
P_ENG_Q="$(query_count "$PDB_ID" "NOTION_PERSONAL_API_KEY" "Engenheiro de Prompt" "Priorizado" "Em andamento")"
S_DIR_Q="$(query_count "$SDB_ID" "NOTION_SMARTENVIOS_API_KEY" "Diretor Tech" "Aguardando" "Priorizado")"
S_ENG_Q="$(query_count "$SDB_ID" "NOTION_SMARTENVIOS_API_KEY" "Engenheiro SmartEnvios" "Priorizado" "Em andamento")"

QUEUE_ACCUMULATING=false
QUEUE_ACCUM_REASON=""
if is_num "$P_DIR_Q" && (( P_DIR_Q >= QUEUE_ALERT_THRESHOLD )); then
  QUEUE_ACCUMULATING=true
  QUEUE_ACCUM_REASON="personal_director_queue"
fi
if [[ "$QUEUE_ACCUMULATING" != "true" ]] && is_num "$P_ENG_Q" && (( P_ENG_Q >= QUEUE_ALERT_THRESHOLD )); then
  QUEUE_ACCUMULATING=true
  QUEUE_ACCUM_REASON="eng_prompt_queue"
fi
if [[ "$QUEUE_ACCUMULATING" != "true" ]] && is_num "$S_DIR_Q" && (( S_DIR_Q >= QUEUE_ALERT_THRESHOLD )); then
  QUEUE_ACCUMULATING=true
  QUEUE_ACCUM_REASON="tech_director_queue"
fi
if [[ "$QUEUE_ACCUMULATING" != "true" ]] && is_num "$S_ENG_Q" && (( S_ENG_Q >= QUEUE_ALERT_THRESHOLD )); then
  QUEUE_ACCUMULATING=true
  QUEUE_ACCUM_REASON="eng_smartenvios_queue"
fi

# Crons críticos
CRITICAL_IDS=(
  c408ba92-a26a-420d-844f-64448f983d93
  99de71d1-97b0-48d0-933e-7fcacfda2184
  e4cd9635-efdd-4588-8ecc-523a4a50ea20
  985165be-59eb-46e7-8715-17571c8e8227
  a7b8c9d0-e1f2-3456-7890-abcdef123401
)

critical_fail=0
critical_total=0
critical_lines=()
for id in "${CRITICAL_IDS[@]}"; do
  row="$(jq -r --arg id "$id" '.jobs[] | select(.id==$id) | [(.name//"?"), (.state.lastStatus//"unknown"), ((.state.consecutiveErrors//0)|tostring), ((.state.lastDurationMs//0)|tostring)] | @tsv' <<<"$CRON_JSON" 2>/dev/null || true)"
  if [[ -n "$row" ]]; then
    critical_total=$((critical_total+1))
    name="${row%%$'\t'*}"
    rest="${row#*$'\t'}"
    status="${rest%%$'\t'*}"; rest2="${rest#*$'\t'}"
    cerr="${rest2%%$'\t'*}"; dur="${rest2#*$'\t'}"
    critical_lines+=("$id|$name|$status|$cerr|$dur")
    if [[ "$status" != "ok" ]] || [[ "$cerr" =~ ^[0-9]+$ && "$cerr" -gt 0 ]]; then
      critical_fail=$((critical_fail+1))
    fi
  fi
done

UNSTABLE=false
reason=()
if [[ "$GATEWAY_OK" != true ]]; then
  UNSTABLE=true
  reason+=("gateway")
fi
if (( critical_fail > 0 )); then
  UNSTABLE=true
  reason+=("critical_crons")
fi
if [[ "${MAIL_STUCK}" == true ]]; then
  UNSTABLE=true
  reason+=("mail_stuck:${MAIL_STUCK_REASON}")
fi
if [[ "${QUEUE_ACCUMULATING}" == true ]]; then
  UNSTABLE=true
  reason+=("queue_accumulating:${QUEUE_ACCUM_REASON}")
fi

RECOVERY_ACTION="none"
RECOVERY_OUT=""
if [[ "$UNSTABLE" == true ]]; then
  if [[ "${QUEUE_ACCUMULATING}" == true ]]; then
    RECOVERY_ACTION="queue-burst-drain"
    RECOVERY_OUT="$(
      {
        echo "[queue-drain] director-personal"
        run_timed 90 bash "$SCRIPT_DIR/director-personal-deterministic-cycle.sh" || true
        echo "[queue-drain] eng-prompt"
        run_timed 120 bash "$SCRIPT_DIR/eng-prompt-deterministic-cycle.sh" || true
        echo "[queue-drain] director-tech"
        run_timed 90 bash "$SCRIPT_DIR/director-tech-deterministic-cycle.sh" || true
        echo "[queue-drain] eng-smartenvios"
        run_timed 120 bash "$SCRIPT_DIR/eng-smartenvios-deterministic-cycle.sh" || true
      } 2>&1
    )"
  elif [[ "${MAIL_STUCK}" == true ]]; then
    RECOVERY_ACTION="mail-self-heal"
    RECOVERY_OUT="$(
      {
        echo "[self-heal] president-mail-demand-cycle"
        run_timed 120 bash "$SCRIPT_DIR/president-mail-demand-cycle.sh" || true
        echo "[self-heal] process-notion-cards personal"
        run_timed 120 bash "$SCRIPT_DIR/gmail/process-notion-cards.sh" personal 15 || true
        echo "[self-heal] process-notion-cards pro"
        run_timed 120 bash "$SCRIPT_DIR/gmail/process-notion-cards.sh" pro 15 || true
      } 2>&1
    )"
  else
    RECOVERY_ACTION="governance-check"
    RECOVERY_OUT="$(run_timed 180 bash "$SCRIPT_DIR/governance-check.sh" 2>&1 || true)"
  fi
fi

# Optional baseline analysis snapshot
ANALYZE_OUT="$(run_timed 60 bash "$SCRIPT_DIR/analyze-cron-logs.sh" 20 2>&1 || true)"

python3 - "$REPORT_JSON" "$TS" "$GATEWAY_OK" "$critical_total" "$critical_fail" "$UNSTABLE" "$RECOVERY_ACTION" <<'PY'
import json,sys
p,ts,gok,ct,cf,unstable,act=sys.argv[1:8]
obj={
  "ts":ts,
  "gatewayOk": gok.lower()=="true",
  "criticalTotal": int(ct),
  "criticalFail": int(cf),
  "unstable": unstable.lower()=="true",
  "recoveryAction": act,
}
with open(p,'w',encoding='utf-8') as f:
  json.dump(obj,f,ensure_ascii=False,indent=2)
print(json.dumps(obj,ensure_ascii=False))
PY

{
  echo "# Stability Cycle $TS"
  echo
  echo "- gateway_ok: $GATEWAY_OK"
  echo "- critical_total: $critical_total"
  echo "- critical_fail: $critical_fail"
  echo "- unstable: $UNSTABLE"
  echo "- recovery_action: $RECOVERY_ACTION"
  echo
  echo "## Critical crons"
  for l in "${critical_lines[@]}"; do
    IFS='|' read -r id name st ce dur <<<"$l"
    echo "- $name ($id): status=$st consecutiveErrors=$ce lastDurationMs=$dur"
  done
  echo
  echo "## Gateway"
  echo '```'
  echo "$GATEWAY_RAW"
  echo '```'
  echo
  echo "## Mail probes"
  echo "- pro: backlog=${MAIL_PRO_BACKLOG:-n/a} cards=${MAIL_PRO_CARDS:-n/a} msg=${MAIL_PRO_MSG:-n/a}"
  echo "- personal: backlog=${MAIL_PERSON_BACKLOG:-n/a} cards=${MAIL_PERSON_CARDS:-n/a} msg=${MAIL_PERSON_MSG:-n/a}"
  echo
  echo "## Queue probes"
  echo "- personal: diretor=${P_DIR_Q:-n/a} eng_prompt=${P_ENG_Q:-n/a}"
  echo "- smart: diretor_tech=${S_DIR_Q:-n/a} eng_smartenvios=${S_ENG_Q:-n/a}"
  echo
  echo "## Recovery output"
  echo '```'
  echo "$RECOVERY_OUT"
  echo '```'
} > "$REPORT_MD"

if [[ "$UNSTABLE" == true ]]; then
  echo "STATUS: ALERTA"
  echo "ACAO: monitoramento detectou instabilidade (${reason[*]}) e acionou governança."
  echo "RESULTADO: relatório salvo em $REPORT_MD"
  echo "PROXIMO: manter ciclo de 10 min até critical_fail=0 e gateway_ok=true de forma consistente."
else
  echo "STATUS: OK"
  echo "ACAO: monitoramento executado sem instabilidade crítica."
  echo "RESULTADO: relatório salvo em $REPORT_MD"
  echo "PROXIMO: continuar ciclo de 10 min para prevenção."
fi
