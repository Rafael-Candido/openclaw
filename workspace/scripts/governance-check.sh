#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# governance-check.sh — Health check + recovery + escalonamento automático
#
# Princípio: resolver na raiz. Não adicionar fallbacks nem nova criticidade.
# Se um cron não cumpre o papel (e-mail acumulado, card travado, etc.),
# corrigir o processo principal (script, payload, frequência, gateway).
# Recovery (wake, force chain) é paliativo até a causa raiz ser corrigida;
# evitar sobrecarregar o ecossistema com mais alternativas.
###############################################################################

LOG_PREFIX="[governance]"
MAX_CONSECUTIVE_ERRORS=2
MAX_RUNNING_MIN=20
MAX_PRIORIZED_MIN=30
MIN_GAP_MS=180000  # 3min mínimo entre crons (evita rate limit, execução sequencial)
MAX_LOCK_MIN=5
REPORT=""
NOTION_QUALITY_SUMMARY="OK"
OPERATIONAL_HEALTH_STATUS="OK"   # OK | ALERTA | CRÍTICO — reflete resultado real dos papéis, não só "cron rodou"
OPERATIONAL_HEALTH_ISSUES=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_GUARD="${PROJECT_ROOT}/workspace/scripts/runtime-guard.sh"
PRUNE_LOGS_SCRIPT="${PROJECT_ROOT}/workspace/scripts/prune-generated-logs.sh"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi

if [[ -x "${RUNTIME_GUARD}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_GUARD}"
  if ! ocw_guard_acquire_lock "governance-check" "${CRON_LOCK_STALE_SEC:-1800}"; then
    echo "{\"ok\":true,\"action\":\"skipped_already_running\",\"lock\":\"governance-check\"}"
    exit 0
  fi
  trap 'ocw_guard_release_lock' EXIT
fi

# Resilience wrapper for OpenClaw CLI operations (cron run/edit, gateway restart, session reset).
# This is what enables Governanca to executar/derrubar crons autonomamente via script.
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/workspace/scripts/openclaw-helper.sh" 2>/dev/null || true
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}"
NOTION_HELPER_SCRIPT="${PROJECT_ROOT}/workspace/scripts/notion-helper.sh"
GMAIL_SCRIPT="${PROJECT_ROOT}/workspace/scripts/gmail/gmail.sh"
DISCORD_GATEWAY_HEALTH_SCRIPT="${PROJECT_ROOT}/workspace/scripts/discord-gateway-health.sh"
NOTION_PERSONAL_DB_ID="bfcbe7a7a3a745489e605e0762af12a9"
BOTTLENECK_COOLDOWN_SEC="${GOV_BOTTLENECK_COOLDOWN_SEC:-21600}"
RUNTIME_TMP_DIR="${OPENCLAW_CONFIG_DIR}/workspace/tmp"
BOTTLENECK_EVENTS_FILE="${RUNTIME_TMP_DIR}/governance-bottlenecks-${$}.jsonl"
BOTTLENECK_SELECTION_FILE="${RUNTIME_TMP_DIR}/governance-bottlenecks-${$}.selection.json"
BOTTLENECK_BODY_FILE="${RUNTIME_TMP_DIR}/governance-bottlenecks-${$}.body.md"
BOTTLENECK_STATE_FILE="${OPENCLAW_CONFIG_DIR}/.cache/governance-bottlenecks-state.json"
GOV_DAILY_COST_ALERT_BRL="${GOV_DAILY_COST_ALERT_BRL:-50}"
GOV_DAILY_COST_CRITICAL_BRL="${GOV_DAILY_COST_CRITICAL_BRL:-100}"
GOV_COST_USD_BRL="${GOV_COST_USD_BRL:-5.5}"
GOV_COST_OPTIMIZER_TRIGGER_GAP_MS="${GOV_COST_OPTIMIZER_TRIGGER_GAP_MS:-21600000}"
GOV_STAGE_TIMEOUT_NOTION_SEC="${GOV_STAGE_TIMEOUT_NOTION_SEC:-75}"
GOV_STAGE_TIMEOUT_GENERAL_SEC="${GOV_STAGE_TIMEOUT_GENERAL_SEC:-45}"
GOV_NOTION_HTTP_TIMEOUT_SEC="${GOV_NOTION_HTTP_TIMEOUT_SEC:-12}"
GOV_NOTION_RECOVERY_LIMIT="${GOV_NOTION_RECOVERY_LIMIT:-1}"                 # processar 1 card mais velho por rodada/status
GOV_PAUSED_RECOVERY_LIMIT="${GOV_PAUSED_RECOVERY_LIMIT:-2}"                 # quantidade máxima de cards Pausado recuperados por rodada (global)
GOV_ENG_PROMPT_STUCK_MIN="${GOV_ENG_PROMPT_STUCK_MIN:-20}"                  # minutos para considerar Em andamento do Eng. Prompt como travado
GOV_ENG_PROMPT_IMPEDIMENTO_MIN="${GOV_ENG_PROMPT_IMPEDIMENTO_MIN:-240}"     # acima disso, mover para Impedimento
GOV_ENG_SMART_STUCK_MIN="${GOV_ENG_SMART_STUCK_MIN:-30}"                    # minutos para considerar Em andamento do Eng. SmartEnvios como travado
GOV_CONCLUDED_AUDIT_WINDOW_MIN="${GOV_CONCLUDED_AUDIT_WINDOW_MIN:-360}"     # janela (min) para auditar concluidos sem evidência
GOV_CONCLUDED_AUDIT_LIMIT="${GOV_CONCLUDED_AUDIT_LIMIT:-30}"                # cards concluidos recentes a auditar por DB
GOV_CONCLUDED_REOPEN_LIMIT="${GOV_CONCLUDED_REOPEN_LIMIT:-2}"               # reabrir no máximo N cards por rodada
GOV_MCP_AUDIT_TIMEOUT_SEC="${GOV_MCP_AUDIT_TIMEOUT_SEC:-90}"                # timeout etapa auditoria MCP

OPTIMIZER_CRON="59c24991-af6c-4df2-95fe-bbf012cd73c0"
MAIL_PRO_CRON="99de71d1-97b0-48d0-933e-7fcacfda2184"
MAIL_PERSON_CRON="e4cd9635-efdd-4588-8ecc-523a4a50ea20"
ENG_PROMPT_CRON="6bdd82c7-081d-486b-9700-0572b9fce72e"
ENG_SMARTENVIOS_CRON="a7b8c9d0-e1f2-3456-7890-abcdef123401"
ESP_SUPORTE_SOFTWARE_CRON="826653ae-7b20-43e2-adf0-90c96a60a6ec"
PRESIDENT_CRON="985165be-59eb-46e7-8715-17571c8e8227"
DIRECTOR_TECH_CRON="7fba5b1f-2ee9-4b1e-aae0-bd211c32b925"
DIRECTOR_PERSONAL_CRON="a71c2958-e52f-4f37-9876-bedf6dcb9434"
DIRECTOR_NEGOCIOS_CRON="cf343b94-0816-42e5-b3dc-d40ecf12786e"

log() { echo "${LOG_PREFIX} $(date -u +%H:%M:%S) $*"; }
report() { REPORT="${REPORT}\n$*"; }

# Governance uses stricter Notion helper timeouts to avoid stalling the whole round.
export NOTION_CURL_TIMEOUT="${NOTION_CURL_TIMEOUT:-${GOV_NOTION_HTTP_TIMEOUT_SEC}}"
export NOTION_MAX_RETRIES="${NOTION_MAX_RETRIES:-2}"
export NOTION_BASE_DELAY="${NOTION_BASE_DELAY:-1}"
export NOTION_MAX_JITTER="${NOTION_MAX_JITTER:-2}"

stage_deadline() {
  local timeout_sec="${1:-30}"
  python3 - "$timeout_sec" <<'PY'
import sys, time
print(int(time.time()) + int(float(sys.argv[1])))
PY
}

stage_expired() {
  local deadline="${1:-0}"
  local now
  now="$(date +%s)"
  [[ "${deadline}" =~ ^[0-9]+$ ]] || return 1
  (( now >= deadline ))
}

# Guardrails for autonomous recovery behavior.
GOV_SESSION_OVERFLOW_PCT="${GOV_SESSION_OVERFLOW_PCT:-150}" # percentUsed >= this => reset session
GOV_DISABLE_CRON_ON_CONFIG_ERROR="${GOV_DISABLE_CRON_ON_CONFIG_ERROR:-true}"
GOV_GATEWAY_RESTART_ON_PRESSURE="${GOV_GATEWAY_RESTART_ON_PRESSURE:-false}" # prefer reset sessions first; restart only if needed
GOV_FORCE_CRON_RUN_ON_RECOVERY="${GOV_FORCE_CRON_RUN_ON_RECOVERY:-false}"   # wake-first; run only as fallback
GOV_WAKE_MIN_GAP_SEC="${GOV_WAKE_MIN_GAP_SEC:-120}"                          # 2min por cron entre wakes (backlog response)
GOV_WAKE_BUDGET_PER_ROUND="${GOV_WAKE_BUDGET_PER_ROUND:-8}"                  # limite de wakes por rodada
GOV_WAKE_TIMEOUT_MS="${GOV_WAKE_TIMEOUT_MS:-6000}"                           # timeout curto para evitar bloqueio
GOV_USE_SAFE_RUN_FALLBACK="${GOV_USE_SAFE_RUN_FALLBACK:-true}"               # fallback para cron-safe-run em falha de wake/run direto
GOV_MAIL_CHAIN_FORCE_COOLDOWN_SEC="${GOV_MAIL_CHAIN_FORCE_COOLDOWN_SEC:-900}" # evita tempestade de forçar cadeia (15min)
GOV_GATEWAY_TOKEN_MISMATCH_THRESHOLD="${GOV_GATEWAY_TOKEN_MISMATCH_THRESHOLD:-8}" # eventos por janela
GOV_GATEWAY_DISCORD_CLOSE_THRESHOLD="${GOV_GATEWAY_DISCORD_CLOSE_THRESHOLD:-8}"    # eventos por janela
GOV_GATEWAY_RECOVERY_WINDOW_MIN="${GOV_GATEWAY_RECOVERY_WINDOW_MIN:-15}"           # janela de análise dos eventos
GOV_GATEWAY_RECOVERY_COOLDOWN_SEC="${GOV_GATEWAY_RECOVERY_COOLDOWN_SEC:-900}"      # evita restart em loop (15min)
GOV_DISCORD_HEALTH_WINDOW_MIN="${GOV_DISCORD_HEALTH_WINDOW_MIN:-20}"                # janela de análise do checker Discord
GOV_DISCORD_LOGIN_STALE_MIN="${GOV_DISCORD_LOGIN_STALE_MIN:-15}"                    # login acima disso vira stale
GOV_DISCORD_ERROR_SCORE_THRESHOLD="${GOV_DISCORD_ERROR_SCORE_THRESHOLD:-3}"          # score para considerar indisponibilidade Discord
GOV_DISCORD_RECOVERY_COOLDOWN_SEC="${GOV_DISCORD_RECOVERY_COOLDOWN_SEC:-900}"       # evita restart em loop da recuperação Discord
GOV_EINSTEIN_CHANNEL_IDS="${GOV_EINSTEIN_CHANNEL_IDS:-690598219587256420}"          # canais Discord monitorados (CSV) para autocura do Einstein
GOV_EINSTEIN_BOT_ID="${GOV_EINSTEIN_BOT_ID:-1439351480514646087}"                   # user id do bot no Discord
GOV_EINSTEIN_RECOVERY_WINDOW_MIN="${GOV_EINSTEIN_RECOVERY_WINDOW_MIN:-1440}"        # janela de análise de menções sem resposta (24h)
GOV_EINSTEIN_RECOVERY_COOLDOWN_SEC="${GOV_EINSTEIN_RECOVERY_COOLDOWN_SEC:-900}"     # evita reprocessamento em loop da mesma menção
GOV_EINSTEIN_PENDING_GRACE_SEC="${GOV_EINSTEIN_PENDING_GRACE_SEC:-120}"             # tolerância antes de acionar autocura
GOV_EINSTEIN_HISTORY_LIMIT="${GOV_EINSTEIN_HISTORY_LIMIT:-150}"                      # limite de mensagens lidas por canal
GOV_EINSTEIN_RECOVERY_TIMEOUT_SEC="${GOV_EINSTEIN_RECOVERY_TIMEOUT_SEC:-240}"       # timeout do agente Einstein na autocura
GOV_EINSTEIN_BACKUP_AGENT_ID="${GOV_EINSTEIN_BACKUP_AGENT_ID:-einstein-backup}"      # agente de contingência para redundância
GOV_EINSTEIN_RECOVERY_RETRY_DELAY_SEC="${GOV_EINSTEIN_RECOVERY_RETRY_DELAY_SEC:-3}"  # pausa curta entre tentativa primária e fallback
GOV_EINSTEIN_RECOVERY_THINKING="${GOV_EINSTEIN_RECOVERY_THINKING:-minimal}"          # thinking level nas tentativas de autocura
GOV_EINSTEIN_FAILURE_NOTIFY="${GOV_EINSTEIN_FAILURE_NOTIFY:-true}"                    # envia aviso no canal quando ambas tentativas falham
GOV_EINSTEIN_RECOVERY_MAX_PER_ROUND="${GOV_EINSTEIN_RECOVERY_MAX_PER_ROUND:-12}"    # limite de menções reprocessadas por rodada
GATEWAY_RESTART_REQUESTED="false"
WOKEN_CRONS="|"
WAKES_USED=0
WAKES_DROPPED=0
GOV_WAKE_STATE_FILE="${OPENCLAW_CONFIG_DIR}/.cache/governance-wake-state.json"
GOV_MAIL_CHAIN_STATE_FILE="${OPENCLAW_CONFIG_DIR}/.cache/governance-mail-chain-state.json"
GOV_GATEWAY_RECOVERY_STATE_FILE="${OPENCLAW_CONFIG_DIR}/.cache/governance-gateway-recovery-state.json"
GOV_DISCORD_RECOVERY_STATE_FILE="${OPENCLAW_CONFIG_DIR}/.cache/governance-discord-recovery-state.json"
GOV_EINSTEIN_RECOVERY_STATE_FILE="${OPENCLAW_CONFIG_DIR}/.cache/governance-einstein-recovery-state.json"
PRESIDENT_FORCE_FILE="/tmp/openclaw-president-force-governance.json"
CRON_SAFE_RUNNER="${PROJECT_ROOT}/workspace/scripts/cron-safe-run.sh"

# Reduz tentativas/bloqueios da camada helper durante pressão.
export OCW_MAX_RETRIES="${OCW_MAX_RETRIES:-2}"
export OCW_BASE_DELAY_SEC="${OCW_BASE_DELAY_SEC:-1}"
export OCW_MAX_DELAY_SEC="${OCW_MAX_DELAY_SEC:-4}"

mkdir -p "${RUNTIME_TMP_DIR}" 2>/dev/null || true
: > "${BOTTLENECK_EVENTS_FILE}"

if [[ -x "${PRUNE_LOGS_SCRIPT}" ]]; then
  "${PRUNE_LOGS_SCRIPT}" "${OPENCLAW_LOG_RETENTION_DAYS:-2}" >/dev/null 2>&1 || true
fi

cleanup_governance_tmp() {
  rm -f "${BOTTLENECK_EVENTS_FILE}" "${BOTTLENECK_SELECTION_FILE}" "${BOTTLENECK_BODY_FILE}" "${NOTION_RECOVERY_CANDIDATES_FILE:-}" 2>/dev/null || true
}
trap cleanup_governance_tmp EXIT

register_bottleneck() {
  local key="$1"
  local severity="$2"
  local title="$3"
  local detail="$4"
  local recommendation="${5:-}"
  [[ -z "${key//[[:space:]]/}" ]] && return
  python3 - "${BOTTLENECK_EVENTS_FILE}" "${key}" "${severity}" "${title}" "${detail}" "${recommendation}" <<'PY'
import json
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
key, severity, title, detail, recommendation = sys.argv[2:7]
event = {
    "key": key.strip(),
    "severity": (severity or "medium").strip().lower(),
    "title": (title or "").strip()[:220],
    "detail": (detail or "").strip()[:1200],
    "recommendation": (recommendation or "").strip()[:1200],
    "observedAt": int(time.time()),
}
with path.open("a", encoding="utf-8") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
}

select_bottlenecks_for_escalation() {
  python3 - "${BOTTLENECK_EVENTS_FILE}" "${BOTTLENECK_STATE_FILE}" "${BOTTLENECK_COOLDOWN_SEC}" <<'PY' > "${BOTTLENECK_SELECTION_FILE}"
import json
import sys
import time
from pathlib import Path

events_path = Path(sys.argv[1])
state_path = Path(sys.argv[2])
cooldown = int(sys.argv[3])
now = int(time.time())
sev_rank = {"low": 1, "medium": 2, "high": 3, "critical": 4}

agg = {}
if events_path.exists():
    for raw in events_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        key = str(ev.get("key") or "").strip()
        if not key:
            continue
        sev = str(ev.get("severity") or "medium").strip().lower()
        if sev not in sev_rank:
            sev = "medium"
        title = str(ev.get("title") or "").strip()
        detail = str(ev.get("detail") or "").strip()
        recommendation = str(ev.get("recommendation") or "").strip()
        observed_at = int(ev.get("observedAt") or now)
        if key not in agg:
            agg[key] = {
                "key": key,
                "severity": sev,
                "title": title,
                "detail": detail,
                "recommendation": recommendation,
                "observedAt": observed_at,
                "runHits": 1,
            }
        else:
            item = agg[key]
            item["runHits"] += 1
            if sev_rank[sev] > sev_rank[item["severity"]]:
                item["severity"] = sev
            if title:
                item["title"] = title
            if detail:
                item["detail"] = detail
            if recommendation:
                item["recommendation"] = recommendation
            if observed_at > int(item.get("observedAt") or 0):
                item["observedAt"] = observed_at

state = {}
if state_path.exists():
    try:
        raw_state = json.loads(state_path.read_text(encoding="utf-8"))
        if isinstance(raw_state, dict):
            state = {str(k): int(v) for k, v in raw_state.items() if str(v).isdigit() or isinstance(v, int)}
    except Exception:
        state = {}

due = []
held = []
for key, item in agg.items():
    last = int(state.get(key, 0))
    elapsed = now - last if last > 0 else cooldown + 1
    if elapsed >= cooldown:
        due.append(item)
    else:
        hold = dict(item)
        hold["nextEligibleInSec"] = max(1, cooldown - elapsed)
        held.append(hold)

due.sort(key=lambda x: (-sev_rank.get(x.get("severity", "medium"), 2), x.get("title", "")))
held.sort(key=lambda x: (-sev_rank.get(x.get("severity", "medium"), 2), x.get("title", "")))

print(json.dumps({
    "due": due,
    "held": held,
    "dueCount": len(due),
    "heldCount": len(held),
    "cooldownSec": cooldown,
    "generatedAt": now,
}, ensure_ascii=False))
PY
}

build_bottleneck_body_file() {
  python3 - "${BOTTLENECK_SELECTION_FILE}" "${BOTTLENECK_BODY_FILE}" <<'PY'
import datetime
import json
import sys
from pathlib import Path

selection = Path(sys.argv[1])
output = Path(sys.argv[2])
try:
    data = json.loads(selection.read_text(encoding="utf-8"))
except Exception:
    data = {"due": []}

due = data.get("due", []) or []
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
lines = [
    "## Objetivo",
    "Governança detectou gargalos recorrentes automaticamente e está escalando melhoria estrutural para eliminar causa raiz.",
    "",
    "## Gargalos detectados na rodada",
]

if not due:
    lines.append("- Nenhum gargalo elegível para escalonamento.")
else:
    for item in due:
        sev = str(item.get("severity", "medium")).upper()
        title = str(item.get("title", "")).strip() or item.get("key", "gargalo")
        detail = str(item.get("detail", "")).strip()
        hits = int(item.get("runHits", 1))
        lines.append(f"- [{sev}] {title} (ocorrências na rodada: {hits})")
        if detail:
            lines.append(f"  Evidência: {detail[:350]}")

lines.extend([
    "",
    "## Ações recomendadas",
])
for item in due:
    reco = str(item.get("recommendation", "")).strip()
    title = str(item.get("title", "")).strip() or item.get("key", "gargalo")
    if reco:
        lines.append(f"- {title}: {reco[:350]}")

lines.extend([
    "",
    "## Critério de aceite",
    "- Remover o gargalo de forma estrutural (script/prompt/cron/padrão).",
    "- Validar em pelo menos 3 execuções da governança sem reincidência.",
    "",
    "## Metadados",
    f"- Rodada da governança: {now}",
    f"- Total de gargalos escalados: {len(due)}",
])

output.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

mark_bottlenecks_escalated() {
  python3 - "${BOTTLENECK_SELECTION_FILE}" "${BOTTLENECK_STATE_FILE}" <<'PY'
import json
import sys
import time
from pathlib import Path

selection = Path(sys.argv[1])
state_path = Path(sys.argv[2])
now = int(time.time())

try:
    data = json.loads(selection.read_text(encoding="utf-8"))
except Exception:
    data = {"due": []}

try:
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {}
except Exception:
    state = {}
if not isinstance(state, dict):
    state = {}

for item in data.get("due", []) or []:
    key = str(item.get("key") or "").strip()
    if key:
        state[key] = now

state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
PY
}

get_notion_block_count() {
  local page_id="$1"
  [[ -z "${page_id:-}" ]] && {
    echo 0
    return 0
  }
  local blocks_json
  blocks_json="$("${NOTION_HELPER_SCRIPT}" get-blocks "${page_id}" NOTION_PERSONAL_API_KEY 2>/dev/null || echo '{"results":[]}')"
  echo "${blocks_json}" | jq -r '.results | length' 2>/dev/null || echo 0
}

# Extrai o corpo de uma página Notion (blocos → texto markdown-like) e grava em arquivo.
# Uso: notion_page_to_body_file <page_id> <api_key_var> <output_file>
# Retorna 0 se conseguiu extrair conteúdo não vazio, 1 caso contrário.
notion_page_to_body_file() {
  local page_id="$1"
  local api_key_var="${2:-NOTION_PERSONAL_API_KEY}"
  local out_file="${3:-}"
  [[ -z "${page_id:-}" || -z "${out_file:-}" ]] && return 1

  local blocks_json
  blocks_json="$("${NOTION_HELPER_SCRIPT}" get-blocks "${page_id}" "${api_key_var}" 2>/dev/null || echo '{"results":[]}')"
  echo "${blocks_json}" | python3 - "${out_file}" <<'PY'
import json
import sys
from pathlib import Path

data = json.load(sys.stdin)
out_path = Path(sys.argv[1])
lines = []
for block in data.get("results") or []:
    t = block.get("type") or "paragraph"
    rich = (block.get(t) or {}).get("rich_text") or []
    text = "".join(r.get("plain_text", "") for r in rich).strip()
    if not text:
        continue
    if t == "heading_1":
        lines.append("## " + text)
    elif t == "heading_2":
        lines.append("## " + text)
    elif t == "heading_3":
        lines.append("### " + text)
    elif t == "bulleted_list_item":
        lines.append("- " + text)
    elif t == "numbered_list_item":
        lines.append("1. " + text)
    else:
        lines.append(text)
out_path.write_text("\n".join(lines), encoding="utf-8")
sys.exit(0 if lines else 1)
PY
}

ensure_minimum_technical_context() {
  local page_id="$1"
  local title="${2:-Card técnico}"
  [[ -z "${page_id:-}" ]] && return 1

  local block_count min_body_file
  block_count="$(get_notion_block_count "${page_id}")"
  [[ ! "${block_count}" =~ ^[0-9]+$ ]] && block_count=0
  if (( block_count >= 3 )); then
    return 0
  fi

  min_body_file="${RUNTIME_TMP_DIR}/governance-min-body-${$}.md"
  cat > "${min_body_file}" <<EOF
## Objetivo
Executar melhoria técnica com contexto suficiente para evitar execução cega.

## Contexto do card
- Título: ${title}
- Origem: Governança automática.

## Escopo mínimo obrigatório
- Identificar causa raiz.
- Definir ação estrutural (prompt/script/cron/padrão).
- Executar ou propor ajuste implementável.

## Critério de aceite
- Evidenciar alteração aplicada.
- Validar em novas rodadas da governança sem reincidência.
EOF
  "${NOTION_HELPER_SCRIPT}" append-body "${page_id}" NOTION_PERSONAL_API_KEY "${min_body_file}" >/dev/null 2>&1 || true

  block_count="$(get_notion_block_count "${page_id}")"
  [[ ! "${block_count}" =~ ^[0-9]+$ ]] && block_count=0
  (( block_count >= 3 ))
}

auto_escalate_bottlenecks_to_notion() {
  if [[ ! -s "${BOTTLENECK_EVENTS_FILE}" ]]; then
    report "✅ Gargalos recorrentes: nenhuma ocorrência para escalonar"
    return
  fi

  if [[ ! -x "${NOTION_HELPER_SCRIPT}" || -z "${NOTION_PERSONAL_API_KEY:-}" ]]; then
    report "⚠️ Escalonamento automático de gargalos indisponível (notion-helper/API key ausente)"
    return
  fi

  select_bottlenecks_for_escalation
  local due_count held_count
  local query_json existing_card_id card_id created_json title now_local matching_ids matching_count notion_priority
  due_count="$(jq -r '.dueCount // 0' "${BOTTLENECK_SELECTION_FILE}" 2>/dev/null || echo 0)"
  held_count="$(jq -r '.heldCount // 0' "${BOTTLENECK_SELECTION_FILE}" 2>/dev/null || echo 0)"

  if [[ ! "${due_count}" =~ ^[0-9]+$ ]]; then due_count=0; fi
  if [[ ! "${held_count}" =~ ^[0-9]+$ ]]; then held_count=0; fi

  query_json="$(NOTION_CACHE_ENABLED=false "${NOTION_HELPER_SCRIPT}" query "${NOTION_PERSONAL_DB_ID}" NOTION_PERSONAL_API_KEY "Engenheiro de Prompt" Priorizado "Em andamento" 2>/dev/null || echo '{"results":[]}')"
  matching_ids="$(echo "${query_json}" | jq -r '[.results[]? | select(((.properties.Name.title[0].plain_text // "") | startswith("[Governança][Melhoria] Gargalos operacionais"))) | {id:(.id // ""), edited:(.last_edited_time // "")}] | sort_by(.edited) | reverse | .[] | .id')"
  matching_count="$(printf '%s\n' "${matching_ids}" | sed '/^$/d' | wc -l | tr -d ' ')"
  existing_card_id="$(printf '%s\n' "${matching_ids}" | sed -n '1p')"

  if [[ "${matching_count:-0}" =~ ^[0-9]+$ ]] && (( matching_count > 1 )); then
    while IFS= read -r duplicate_id; do
      [[ -z "${duplicate_id}" || "${duplicate_id}" == "${existing_card_id}" ]] && continue
      "${NOTION_HELPER_SCRIPT}" comment "${duplicate_id}" NOTION_PERSONAL_API_KEY "Fechando card duplicado de gargalos; mantendo card mais recente para continuidade." "Governança" >/dev/null 2>&1 || true
      "${NOTION_HELPER_SCRIPT}" update-status "${duplicate_id}" NOTION_PERSONAL_API_KEY "Concluído" >/dev/null 2>&1 || true
    done <<< "${matching_ids}"
    report "🧹 Melhoria autônoma: duplicatas de card de gargalo consolidadas (mantido=${existing_card_id})"
  fi

  if (( due_count == 0 )); then
    if (( held_count > 0 )); then
      report "ℹ️ Gargalos detectados, porém em cooldown (${held_count} item(ns) aguardando janela)"
    else
      report "✅ Gargalos recorrentes: nenhum item elegível para escalonamento"
    fi
    return
  fi

  notion_priority="$(python3 - "${BOTTLENECK_SELECTION_FILE}" <<'PY'
import json
import sys

try:
    data = json.loads(open(sys.argv[1], encoding="utf-8").read())
except Exception:
    data = {"due": []}

priority_rank = {"Baixa": 1, "Média": 2, "Alta": 3}
severity_map = {
    "critical": "Alta",
    "high": "Alta",
    "medium": "Média",
    "low": "Baixa",
}

best = "Média"
for item in data.get("due", []) or []:
    sev = str(item.get("severity", "medium")).strip().lower()
    candidate = severity_map.get(sev, "Média")
    if priority_rank[candidate] > priority_rank[best]:
        best = candidate

print(best)
PY
)"
  [[ -z "${notion_priority:-}" ]] && notion_priority="Média"

  build_bottleneck_body_file
  if [[ ! -s "${BOTTLENECK_BODY_FILE}" ]] || ! grep -q '[^[:space:]]' "${BOTTLENECK_BODY_FILE}"; then
    report "⚠️ Melhoria autônoma: descrição técnica vazia, card não será criado/atualizado"
    register_bottleneck "governance-empty-bottleneck-body" "high" "Gargalo sem descrição técnica gerada" "Governança detectou tentativa de escalonamento sem corpo descritivo válido." "Bloquear criação de card vazio e revisar geração do body de gargalos."
    return
  fi

  card_id=""
  if [[ -n "${existing_card_id}" ]]; then
    local comment_msg
    comment_msg="$(python3 - "${BOTTLENECK_SELECTION_FILE}" <<'PY'
import json
import sys
from datetime import datetime

try:
    data = json.loads(open(sys.argv[1], encoding="utf-8").read())
except Exception:
    data = {"due": []}

due = data.get("due", []) or []
stamp = datetime.now().strftime("%d/%m %H:%M")
lines = [f"Atualização automática da Governança ({stamp}) com gargalos recorrentes detectados:"]
for item in due[:6]:
    sev = str(item.get("severity", "medium")).upper()
    title = str(item.get("title", "")).strip() or item.get("key", "gargalo")
    lines.append(f"- [{sev}] {title}")
msg = "\n".join(lines)
print(msg[:1800])
PY
)"
    "${NOTION_HELPER_SCRIPT}" comment "${existing_card_id}" NOTION_PERSONAL_API_KEY "${comment_msg}" "Governança" >/dev/null 2>&1 || true
    "${NOTION_HELPER_SCRIPT}" append-body "${existing_card_id}" NOTION_PERSONAL_API_KEY "${BOTTLENECK_BODY_FILE}" >/dev/null 2>&1 || true
    "${NOTION_HELPER_SCRIPT}" update-priority "${existing_card_id}" NOTION_PERSONAL_API_KEY "${notion_priority}" >/dev/null 2>&1 || true
    card_id="${existing_card_id}"
    report "🧩 Melhoria autônoma: card existente atualizado no Notion Pessoal (Engenheiro de Prompt, prioridade=${notion_priority})"
  else
    now_local="$(date '+%d/%m %H:%M')"
    title="[Governança][Melhoria] Gargalos operacionais recorrentes ${now_local}"
    created_json="$("${NOTION_HELPER_SCRIPT}" create-card "${NOTION_PERSONAL_DB_ID}" NOTION_PERSONAL_API_KEY "${title}" Priorizado OpenClaw "Engenheiro de Prompt" "${notion_priority}" "Governança" "${BOTTLENECK_BODY_FILE}" 2>/dev/null || true)"
    card_id="$(echo "${created_json}" | jq -r '.id // empty' 2>/dev/null || true)"
    if [[ -n "${card_id}" ]]; then
      # Reforço idempotente: garante corpo mesmo se o create-card não anexar por intermitência da API.
      "${NOTION_HELPER_SCRIPT}" append-body "${card_id}" NOTION_PERSONAL_API_KEY "${BOTTLENECK_BODY_FILE}" >/dev/null 2>&1 || true
      "${NOTION_HELPER_SCRIPT}" comment "${card_id}" NOTION_PERSONAL_API_KEY "Card de melhoria aberto automaticamente com base nos gargalos desta rodada." "Governança" >/dev/null 2>&1 || true
      report "🧩 Melhoria autônoma: card criado no Notion Pessoal para Engenheiro de Prompt (id=${card_id}, prioridade=${notion_priority})"
    else
      report "⚠️ Melhoria autônoma: falha ao criar card de gargalos no Notion Pessoal"
      return
    fi
  fi

  # Guardrail final: não deixar card técnico da Governança sem descrição útil.
  if ! ensure_minimum_technical_context "${card_id}" "${title:-[Governança][Melhoria]}"; then
    "${NOTION_HELPER_SCRIPT}" update-status "${card_id}" NOTION_PERSONAL_API_KEY "Aguardando" >/dev/null 2>&1 || true
    "${NOTION_HELPER_SCRIPT}" comment "${card_id}" NOTION_PERSONAL_API_KEY "Governança bloqueou priorização automática: card ficou sem descrição técnica suficiente após tentativa de enriquecimento. Corrigir geração de contexto antes de repriorizar." "Governança" >/dev/null 2>&1 || true
    report "🧱 Melhoria autônoma: card sem descrição suficiente foi bloqueado em Aguardando (id=${card_id})"
    register_bottleneck "governance-created-card-no-context" "high" "Card criado pela Governança sem contexto técnico suficiente" "Card ${card_id} ficou com corpo insuficiente após criação/atualização automática e foi bloqueado." "Garantir corpo mínimo obrigatório com objetivo, escopo e critérios antes de priorizar cards técnicos."
    return
  fi

  mark_bottlenecks_escalated
  report "📌 Gargalos escalados automaticamente: ${due_count} (cooldown=${BOTTLENECK_COOLDOWN_SEC}s)"
}

quarantine_empty_eng_prompt_cards() {
  if [[ -z "${NOTION_PERSONAL_API_KEY:-}" || ! -x "${NOTION_HELPER_SCRIPT}" ]]; then
    return
  fi

  local deadline cards_json
  deadline="$(stage_deadline "${GOV_STAGE_TIMEOUT_NOTION_SEC}")"
  cards_json="$(python3 - "${NOTION_PERSONAL_API_KEY}" "${NOTION_PERSONAL_DB_ID}" "${GOV_NOTION_HTTP_TIMEOUT_SEC}" "${deadline}" <<'PY'
import json
import sys
import time
import urllib.request

api_key, db_id, req_timeout, deadline = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
headers = {
    "Authorization": f"Bearer {api_key}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}
payload = {
    "page_size": 100,
    "filter": {
        "and": [
            {"property": "Tipo", "select": {"equals": "OpenClaw"}},
            {"or": [
                {"property": "Status", "select": {"equals": "Aguardando"}},
                {"property": "Status", "select": {"equals": "Priorizado"}},
                {"property": "Status", "select": {"equals": "Em andamento"}}
            ]}
        ]
    }
}
rows = []
cursor = None
timed_out = False
for _ in range(8):
    if time.time() >= deadline:
        timed_out = True
        break
    body = dict(payload)
    if cursor:
        body["start_cursor"] = cursor
    req = urllib.request.Request(
        f"https://api.notion.com/v1/databases/{db_id}/query",
        data=json.dumps(body).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=req_timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    rows.extend(data.get("results", []))
    if not data.get("has_more"):
        break
    cursor = data.get("next_cursor")
    if not cursor:
        break
print(json.dumps({"results": rows, "timedOut": timed_out}, ensure_ascii=False))
PY
)" || cards_json='{"results":[],"timedOut":true}'

  if [[ "$(echo "${cards_json}" | jq -r '.timedOut // false' 2>/dev/null)" == "true" ]]; then
    report "⏱️ Limpeza Notion pessoal: orçamento de tempo atingido; execução parcial aplicada"
    register_bottleneck "notion-cleanup-time-budget" "medium" "Limpeza de cards sem descrição parcialmente executada" "Varredura do Notion pessoal atingiu limite de tempo da etapa." "Ajustar paginação/timeout para manter execução completa sem travar rodada."
  fi

  local affected=0 scanned=0
  while IFS='|' read -r page_id title status agent; do
    [[ -z "${page_id}" ]] && continue
    scanned=$((scanned + 1))
    if stage_expired "${deadline}"; then
      report "⏱️ Limpeza Notion pessoal interrompida por timeout interno (scanned=${scanned}, fixed=${affected})"
      register_bottleneck "notion-cleanup-enrichment-timeout" "medium" "Enriquecimento de cards sem descrição interrompido por timeout" "Processamento da limpeza atingiu orçamento de tempo após ${scanned} cards (corrigidos=${affected})." "Continuar em rodadas seguintes e manter limite por etapa."
      break
    fi

    # Varredura automática: foco em cards da Governança e tarefas do Eng. de Prompt.
    if [[ "${agent}" != "Engenheiro de Prompt" && "${title}" != \[Governança\]\[Melhoria\]* ]]; then
      continue
    fi

    local block_count
    block_count="$(get_notion_block_count "${page_id}")"
    [[ ! "${block_count}" =~ ^[0-9]+$ ]] && block_count=0

    if (( block_count < 3 )); then
      if ! ensure_minimum_technical_context "${page_id}" "${title:-sem-título}"; then
        "${NOTION_HELPER_SCRIPT}" update-status "${page_id}" NOTION_PERSONAL_API_KEY "Aguardando" >/dev/null 2>&1 || true
        "${NOTION_HELPER_SCRIPT}" comment "${page_id}" NOTION_PERSONAL_API_KEY "Governança bloqueou execução: card sem descrição técnica suficiente após autoenriquecimento. Reenriquecer antes de priorizar novamente." "Governança" >/dev/null 2>&1 || true
      fi
      affected=$((affected + 1))
      report "🧱 Qualidade Notion: card antigo sem descrição tratado (${title:-sem-título})"
    fi
  done < <(echo "${cards_json}" | jq -r '.results[]? | "\(.id // "")|\(.properties.Name.title[0].plain_text // "")|\(.properties.Status.select.name // "")|\(.properties.Agente.select.name // "")"' 2>/dev/null || true)

  if (( affected > 0 )); then
    register_bottleneck "eng-prompt-cards-empty-body" "high" "Cards antigos sem descrição no Notion Pessoal" "Governança detectou ${affected} card(s) sem contexto técnico suficiente no Notion Pessoal e aplicou enriquecimento/bloqueio." "Garantir body_file obrigatório e descrição mínima em todos os fluxos que criam card para Engenheiro de Prompt/Governança."
  else
    report "✅ Limpeza Notion pessoal: sem cards antigos sem descrição no escopo Engenheiro de Prompt/Governança"
  fi
}

resolve_whatsapp_target() {
  if [[ -n "${OPENCLAW_GOV_WHATSAPP_TARGET:-}" ]]; then
    echo "${OPENCLAW_GOV_WHATSAPP_TARGET}"
    return
  fi

  local config_path="${PROJECT_ROOT}/openclaw.json"
  [[ -f "${config_path}" ]] || return

  python3 - "${config_path}" <<'PY'
import json
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
try:
    data = json.loads(cfg.read_text(encoding="utf-8"))
except Exception:
    print("")
    raise SystemExit

candidates = (
    (((data.get("channels") or {}).get("whatsapp") or {}).get("allowFrom") or [])
)
for raw in candidates:
    if not isinstance(raw, str):
        continue
    cleaned = raw.strip()
    if re.match(r"^\+\d{8,16}$", cleaned):
        print(cleaned)
        raise SystemExit

print("")
PY
}

send_governance_whatsapp_table() {
  local target message panel_json
  target="$(resolve_whatsapp_target)"
  if [[ -z "${target:-}" ]]; then
    report "⚠️ WhatsApp: alvo não configurado (defina OPENCLAW_GOV_WHATSAPP_TARGET ou channels.whatsapp.allowFrom[0])"
    return
  fi

  panel_json="$(python3 - "$CRON_JSON" "$NOTION_QUALITY_SUMMARY" "${OPERATIONAL_HEALTH_STATUS:-OK}" <<'PY'
import datetime
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    print(json.dumps({"text": ""}))
    raise SystemExit
quality = sys.argv[2] if len(sys.argv) > 2 else "OK"
operational = (sys.argv[3] if len(sys.argv) > 3 else "OK").strip() or "OK"

jobs = data.get("jobs", []) if isinstance(data, dict) else []
now_ms = int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000)
local_tz = datetime.datetime.now().astimezone().tzinfo

def trim(s, n):
    s = str(s or "")
    return s if len(s) <= n else s[: n - 1] + "…"

def fmt_last(ms):
    if not ms:
        return "-"
    dt = datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).astimezone(local_tz)
    return dt.strftime("%d/%m %H:%M")

def fmt_next(ms):
    if not ms:
        return "-"
    diff = ms - now_ms
    mins = abs(diff) // 60000
    if diff < 0:
        return f"atraso {mins}m"
    if mins == 0:
        return "<1m"
    return f"{mins}m"

def stage(job):
    if not job.get("enabled", True):
        return "off"
    st = job.get("state") or {}
    running_at = st.get("runningAtMs") or 0
    if running_at > 0:
        elapsed = max(0, (now_ms - running_at) // 60000)
        return f"rodando {elapsed}m"
    last = (st.get("lastRunStatus") or st.get("lastStatus") or "-").lower()
    errs = int(st.get("consecutiveErrors") or 0)
    if last in {"error", "failed", "timeout"}:
        return f"{last} e{errs}"
    if errs > 0:
        return f"{last} e{errs}"
    return last if last and last != "-" else "idle"

rows = []
for j in jobs:
    st = j.get("state") or {}
    last_run_ms = int(st.get("lastRunAtMs") or 0)
    rows.append((
        last_run_ms,
        trim(j.get("agentId") or "?", 9),
        trim(j.get("name") or "?", 26),
        trim(stage(j), 12),
        fmt_next(st.get("nextRunAtMs") or 0),
        fmt_last(last_run_ms),
    ))

# Ordena por "Última" (mais recente primeiro); sem execução fica no final.
rows.sort(key=lambda r: (r[0] == 0, -r[0] if r[0] else 0))
enabled = sum(1 for j in jobs if j.get("enabled", True))
timestamp = datetime.datetime.now(local_tz).strftime("%d/%m/%Y %H:%M")

def stage_emoji(stage_text):
    txt = (stage_text or "").lower()
    if any(word in txt for word in ("error", "fail", "timeout", "falha")):
        return "🔴"
    if any(word in txt for word in ("rodando", "exec", "pend", "idle")):
        return "🟡"
    return "🟢"

lines = [
    "🛡️ Governança | Painel de Crons",
    f"🕒 {timestamp}",
    f"Saúde operacional: {operational}",
    f"Ativos: {enabled}/{len(jobs)}",
    f"Qualidade Notion: {quality}",
    "",
]

for _, a, n, s, nx, lr in rows:
    emoji = stage_emoji(s)
    if emoji == "🟢":
        desc = lr if lr != "-" else "sem exec"
    else:
        desc = s or "-"
    lines.append(f"- {emoji} {trim(n, 32)} - {desc}")

text_panel = "\n".join(lines)[:3500]
print(json.dumps({"text": text_panel}))
PY
)"

  message="$(echo "${panel_json}" | jq -r '.text // ""')"
  [[ -z "${message//[[:space:]]/}" ]] && {
    report "⚠️ WhatsApp: falha ao montar painel de crons em texto"
    return
  }

  if openclaw message send --channel whatsapp --target "${target}" --message "${message}" >/dev/null 2>&1; then
    report "📲 WhatsApp: painel de crons (texto) enviado para ${target}"
  else
    report "⚠️ WhatsApp: falha ao enviar painel de crons (texto) para ${target}"
  fi
}

check_notion_operational_quality() {
  if [[ -z "${NOTION_PERSONAL_API_KEY:-}" || -z "${NOTION_SMARTENVIOS_API_KEY:-}" ]]; then
    report "⚠️ Qualidade Notion: chaves de API ausentes para auditoria operacional"
    register_bottleneck "notion-quality-audit-missing-key" "high" "Auditoria de qualidade Notion indisponível" "Governança não conseguiu auditar backlog/duplicidade por falta de credenciais." "Garantir NOTION_PERSONAL_API_KEY e NOTION_SMARTENVIOS_API_KEY no ambiente do cron."
    NOTION_QUALITY_SUMMARY="ALERTA (credenciais)"
    return
  fi

  local quality_json deadline
  deadline="$(stage_deadline "${GOV_STAGE_TIMEOUT_NOTION_SEC}")"
  quality_json="$(python3 - "${NOTION_PERSONAL_API_KEY}" "${NOTION_SMARTENVIOS_API_KEY}" "${GOV_NOTION_HTTP_TIMEOUT_SEC}" "${deadline}" <<'PY'
import json
import sys
import time
import urllib.request

personal_key = sys.argv[1]
smart_key = sys.argv[2]
http_timeout = int(sys.argv[3])
deadline = int(sys.argv[4])
personal_db = "bfcbe7a7a3a745489e605e0762af12a9"
smart_db = "adec12e735dc41a3bb7c274b287f3a10"
NOTION_VERSION = "2022-06-28"
open_status = {"Aguardando", "Priorizado", "Em andamento"}

def notion_query(db_id, api_key):
    url = f"https://api.notion.com/v1/databases/{db_id}/query"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Notion-Version": NOTION_VERSION,
        "Content-Type": "application/json",
    }
    payload = {
        "page_size": 100,
        "filter": {
            "and": [
                {"property": "Tipo", "select": {"equals": "OpenClaw"}},
                {"or": [
                    {"property": "Status", "select": {"equals": "Aguardando"}},
                    {"property": "Status", "select": {"equals": "Priorizado"}},
                    {"property": "Status", "select": {"equals": "Em andamento"}},
                ]},
            ]
        },
    }
    out = []
    cursor = None
    timed_out = False
    for _ in range(20):
        if time.time() >= deadline:
            timed_out = True
            break
        body = dict(payload)
        if cursor:
            body["start_cursor"] = cursor
        req = urllib.request.Request(
            url,
            data=json.dumps(body).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=http_timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        out.extend(data.get("results", []))
        if not data.get("has_more"):
            break
        cursor = data.get("next_cursor")
        if not cursor:
            break
    return out, timed_out

def title_of(page):
    t = (((page.get("properties") or {}).get("Name") or {}).get("title") or [])
    return "".join(x.get("plain_text", "") for x in t).strip()

def status_of(page):
    return ((((page.get("properties") or {}).get("Status") or {}).get("select") or {}).get("name") or "").strip()

def agent_of(page):
    return ((((page.get("properties") or {}).get("Agente") or {}).get("select") or {}).get("name") or "").strip()

personal, personal_timed_out = notion_query(personal_db, personal_key)
smart, smart_timed_out = notion_query(smart_db, smart_key)

personal_open = []
for p in personal:
    st = status_of(p)
    if st in open_status:
        personal_open.append({
            "id": p.get("id", ""),
            "title": title_of(p),
            "status": st,
            "agent": agent_of(p),
        })

title_map = {}
for p in smart:
    st = status_of(p)
    title = title_of(p)
    if st not in open_status or not title:
        continue
    title_map.setdefault(title, []).append({
        "id": p.get("id", ""),
        "status": st,
        "agent": agent_of(p),
    })

duplicates = [
    {"title": k, "items": v}
    for k, v in title_map.items()
    if len(v) > 1
]

mail_pro_dups = [
    d for d in duplicates
    if d["title"].startswith("[Rotina Mail-Pro]")
]

print(json.dumps({
    "timed_out": bool(personal_timed_out or smart_timed_out),
    "personal_open_count": len(personal_open),
    "personal_open": personal_open[:20],
    "duplicate_open_titles_count": len(duplicates),
    "duplicate_open_titles": duplicates[:10],
    "mail_pro_duplicate_count": len(mail_pro_dups),
    "mail_pro_duplicates": mail_pro_dups[:10],
    "misrouted_eng_prompt_count": sum(1 for p in smart if status_of(p) in open_status and agent_of(p) == "Engenheiro de Prompt"),
    "misrouted_eng_prompt_cards": [
        {
            "id": p.get("id", ""),
            "title": title_of(p),
            "status": status_of(p),
            "agent": agent_of(p),
        }
        for p in smart
        if status_of(p) in open_status and agent_of(p) == "Engenheiro de Prompt"
    ][:50],
    "misrouted_non_tech_directors": [
        {
            "id": p.get("id", ""),
            "title": title_of(p),
            "status": status_of(p),
            "agent": agent_of(p),
        }
        for p in smart
        if status_of(p) in open_status and agent_of(p) in {"Diretor Pessoal", "Diretor Negócios"}
    ][:50],
}, ensure_ascii=False))
PY
)" || true

  if [[ -z "${quality_json//[[:space:]]/}" ]]; then
    report "⚠️ Qualidade Notion: falha ao auditar backlog/duplicidade"
    register_bottleneck "notion-quality-audit-failed" "high" "Falha na auditoria de qualidade Notion" "Governança não conseguiu calcular backlog/duplicidade no Notion." "Verificar disponibilidade da API Notion e robustez da consulta."
    NOTION_QUALITY_SUMMARY="ALERTA (auditoria)"
    return
  fi

  if [[ "$(echo "${quality_json}" | jq -r '.timed_out // false' 2>/dev/null)" == "true" ]]; then
    report "⏱️ Qualidade Notion: orçamento de tempo atingido, auditoria parcial aplicada"
    register_bottleneck "notion-quality-time-budget" "medium" "Auditoria de qualidade Notion parcial por timeout de etapa" "A etapa de qualidade do Notion atingiu o limite de tempo interno e devolveu resultado parcial." "Manter paginação limitada e timeout por etapa para não travar a rodada completa."
  fi

  local personal_count dup_count mail_pro_dup misrouted_eng_prompt misrouted_non_tech_directors
  local fix_limit=8 fixed_count=0
  personal_count="$(echo "${quality_json}" | jq -r '.personal_open_count // 0' 2>/dev/null || echo 0)"
  dup_count="$(echo "${quality_json}" | jq -r '.duplicate_open_titles_count // 0' 2>/dev/null || echo 0)"
  mail_pro_dup="$(echo "${quality_json}" | jq -r '.mail_pro_duplicate_count // 0' 2>/dev/null || echo 0)"
  misrouted_eng_prompt="$(echo "${quality_json}" | jq -r '.misrouted_eng_prompt_count // 0' 2>/dev/null || echo 0)"
  misrouted_non_tech_directors="$(echo "${quality_json}" | jq -r '(.misrouted_non_tech_directors // []) | length' 2>/dev/null || echo 0)"
  [[ ! "${personal_count}" =~ ^[0-9]+$ ]] && personal_count=0
  [[ ! "${dup_count}" =~ ^[0-9]+$ ]] && dup_count=0
  [[ ! "${mail_pro_dup}" =~ ^[0-9]+$ ]] && mail_pro_dup=0
  [[ ! "${misrouted_eng_prompt}" =~ ^[0-9]+$ ]] && misrouted_eng_prompt=0
  [[ ! "${misrouted_non_tech_directors}" =~ ^[0-9]+$ ]] && misrouted_non_tech_directors=0

  if (( misrouted_eng_prompt > 0 )); then
    report "🚨 Qualidade Notion: ${misrouted_eng_prompt} card(s) com Agente=Engenheiro de Prompt no Notion profissional"
    register_bottleneck "misrouted-eng-prompt-smartenvios" "critical" "Roteamento incorreto: Engenheiro de Prompt no Notion profissional" "Detectados ${misrouted_eng_prompt} cards em aberto no SmartEnvios com Agente=Engenheiro de Prompt." "Governança migra automaticamente para Notion Pessoal e encerra o card no profissional. OBRIGATÓRIO corrigir o causador: reforçar trava de roteamento nos crons Presidente e Diretor Tech (mensagem do cron, skill Notion) para que Agente Engenheiro de Prompt nunca seja atribuído no DB SmartEnvios; demandas para Eng. Prompt devem ser criadas apenas no Notion Pessoal. Revisar fluxo que gerou estes cards e eliminar a causa para não reincidir (não só apagar incêndio)."
    local eng_prompt_fixed=0
    if [[ -x "${NOTION_HELPER_SCRIPT}" && -n "${NOTION_PERSONAL_API_KEY:-}" ]]; then
      while IFS='|' read -r page_id page_status page_title; do
        if stage_expired "${deadline}"; then
          report "⏱️ Qualidade Notion: timeout interno durante migração (Engenheiro de Prompt)"
          break
        fi
        if (( fixed_count >= fix_limit )); then
          report "ℹ️ Qualidade Notion: limite de migrações por rodada atingido (${fix_limit})"
          break
        fi
        [[ -z "${page_id}" ]] && continue
        safe_title="${page_title:-sem-título}"
        body_file="${RUNTIME_TMP_DIR}/gov-migrate-body-${$}-${page_id}.md"
        if notion_page_to_body_file "${page_id}" NOTION_SMARTENVIOS_API_KEY "${body_file}" 2>/dev/null && [[ -s "${body_file}" ]]; then
          created_json="$("${NOTION_HELPER_SCRIPT}" create-card "${NOTION_PERSONAL_DB_ID}" NOTION_PERSONAL_API_KEY "${safe_title}" Aguardando OpenClaw "Engenheiro de Prompt" Média "Governança" "${body_file}" 2>/dev/null || true)"
          new_id="$(echo "${created_json}" | jq -r '.id // empty' 2>/dev/null || true)"
          if [[ -n "${new_id}" ]]; then
            if "${NOTION_HELPER_SCRIPT}" update-status "${page_id}" NOTION_SMARTENVIOS_API_KEY "Concluído" >/dev/null 2>&1; then
              notion_url="https://www.notion.so/${new_id}"
              "${NOTION_HELPER_SCRIPT}" comment "${page_id}" NOTION_SMARTENVIOS_API_KEY "Migrado para Notion Pessoal por Governança. Novo card: ${notion_url}" "Governança" >/dev/null 2>&1 || true
              report "    📦 Migrado para Notion Pessoal: '${safe_title}' (origem=${page_id}, novo=${new_id})"
              fixed_count=$((fixed_count + 1))
              eng_prompt_fixed=$((eng_prompt_fixed + 1))
            else
              report "    ⚠️ Card criado no Pessoal (${new_id}) mas falha ao encerrar origem ${page_id}"
            fi
          else
            report "    ⚠️ Falha ao criar card no Pessoal para '${safe_title}'; fallback: normalizar agente no SmartEnvios"
            if "${NOTION_HELPER_SCRIPT}" update-agent "${page_id}" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" >/dev/null 2>&1; then
              "${NOTION_HELPER_SCRIPT}" comment "${page_id}" NOTION_SMARTENVIOS_API_KEY "Governança tentou migrar para Notion Pessoal (falha na criação). Agente normalizado para Diretor Tech; rerotear manualmente se necessário." "Governança" >/dev/null 2>&1 || true
              fixed_count=$((fixed_count + 1))
              eng_prompt_fixed=$((eng_prompt_fixed + 1))
            fi
          fi
          rm -f "${body_file}" 2>/dev/null || true
        else
          if "${NOTION_HELPER_SCRIPT}" update-agent "${page_id}" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" >/dev/null 2>&1; then
            "${NOTION_HELPER_SCRIPT}" comment "${page_id}" NOTION_SMARTENVIOS_API_KEY "Governança normalizou o agente de 'Engenheiro de Prompt' para 'Diretor Tech' porque este card está no Notion profissional (SmartEnvios). Sem corpo extraído para migração; Diretor Tech deve rerotear para o Notion Pessoal quando aplicável." "Governança" >/dev/null 2>&1 || true
            report "    🛠️ Normalizado no SmartEnvios (sem corpo para migrar): '${safe_title}' (Engenheiro de Prompt -> Diretor Tech)"
            fixed_count=$((fixed_count + 1))
            eng_prompt_fixed=$((eng_prompt_fixed + 1))
          else
            report "    ⚠️ Falha ao normalizar card ${page_id} (Engenheiro de Prompt -> Diretor Tech)"
          fi
        fi
      done < <(echo "${quality_json}" | jq -r '.misrouted_eng_prompt_cards[]? | "\(.id)|\(.status)|\(.title)"' 2>/dev/null || true)
    fi
    # Corrigir o causador: além da correção pontual, criar card para eliminar a causa e não reincidir (não só apagar incêndio).
    if (( eng_prompt_fixed > 0 )) && [[ -x "${NOTION_HELPER_SCRIPT}" && -n "${NOTION_PERSONAL_API_KEY:-}" ]]; then
      local causa_raiz_body="${RUNTIME_TMP_DIR}/gov-causa-raiz-eng-prompt-${$}.md"
      cat > "${causa_raiz_body}" <<CAUSARAIZ
## Objetivo
Corrigir o causador do roteamento incorreto: evitar que novos cards com Agente=Engenheiro de Prompt sejam criados no Notion profissional (SmartEnvios). Não só apagar incêndio — eliminar a causa.

## Contexto
Nesta rodada a Governança migrou ou normalizou ${eng_prompt_fixed} card(s) que estavam no SmartEnvios com Agente=Engenheiro de Prompt. Esses cards devem existir apenas no Notion Pessoal.

## Ação obrigatória (causador)
- Revisar e reforçar a **trava de roteamento** nos crons **Presidente** e **Diretor Tech**: a mensagem do cron e o uso do skill Notion devem garantir que Agente "Engenheiro de Prompt" nunca seja atribuído ao DB SmartEnvios.
- Identificar qual fluxo (Presidente ou Diretor Tech) criou ou moveu estes cards para o DB errado e ajustar prompt/regra para não reincidir.
- Documentar a regra em FLUXO_AGENTES.md / templates para que novos crons respeitem o roteamento.

## Critério de aceite
- Nenhum card novo com Agente=Engenheiro de Prompt no Notion profissional nas próximas rodadas de auditoria.
CAUSARAIZ
      created_causa="$("${NOTION_HELPER_SCRIPT}" create-card "${NOTION_PERSONAL_DB_ID}" NOTION_PERSONAL_API_KEY "[Governança][Causa raiz] Eliminar criação de cards Eng. Prompt no Notion profissional" Aguardando OpenClaw "Engenheiro de Prompt" Média "Governança" "${causa_raiz_body}" 2>/dev/null || true)"
      if [[ -n "$(echo "${created_causa}" | jq -r '.id // empty' 2>/dev/null)" ]]; then
        report "    📌 Card de causa raiz criado no Pessoal: corrigir travas nos crons Presidente/Diretor Tech para não reincidir"
      fi
      rm -f "${causa_raiz_body}" 2>/dev/null || true
    fi
    force_cron_wake "${DIRECTOR_TECH_CRON}" || true
    force_cron_wake "${DIRECTOR_PERSONAL_CRON}" || true
    force_cron_wake "${ENG_PROMPT_CRON}" || true
  fi

  if (( misrouted_non_tech_directors > 0 )); then
    report "🚨 Qualidade Notion: ${misrouted_non_tech_directors} card(s) com Agente=Diretor Pessoal/Negócios no Notion profissional"
    register_bottleneck "misrouted-directors-smartenvios" "critical" "Roteamento incorreto: Diretor Pessoal/Negócios no Notion profissional" "Detectados ${misrouted_non_tech_directors} cards em aberto no SmartEnvios com Agente inválido para esse DB." "Governança normaliza para Diretor Tech e comenta. OBRIGATÓRIO corrigir o causador: reforçar trava nos crons Presidente/Diretor Tech para que Agentes Diretor Pessoal e Diretor Negócios nunca sejam usados no DB SmartEnvios; revisar fluxo que criou estes cards para não reincidir."
    if [[ -x "${NOTION_HELPER_SCRIPT}" ]]; then
      while IFS='|' read -r page_id page_agent page_title; do
        if stage_expired "${deadline}"; then
          report "⏱️ Qualidade Notion: timeout interno durante normalização de diretores no SmartEnvios"
          break
        fi
        if (( fixed_count >= fix_limit )); then
          report "ℹ️ Qualidade Notion: limite de correções por rodada atingido (${fix_limit})"
          break
        fi
        [[ -z "${page_id}" ]] && continue
        if "${NOTION_HELPER_SCRIPT}" update-agent "${page_id}" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" >/dev/null 2>&1; then
          "${NOTION_HELPER_SCRIPT}" comment "${page_id}" NOTION_SMARTENVIOS_API_KEY "Governança normalizou o agente de '${page_agent}' para 'Diretor Tech' porque este card está no Notion profissional (SmartEnvios)." "Governança" >/dev/null 2>&1 || true
          report "    🛠️ Normalizado no SmartEnvios: '${page_title:-sem-título}' (${page_agent} -> Diretor Tech)"
          fixed_count=$((fixed_count + 1))
        else
          report "    ⚠️ Falha ao normalizar card ${page_id} (${page_agent} -> Diretor Tech)"
        fi
      done < <(echo "${quality_json}" | jq -r '.misrouted_non_tech_directors[]? | "\(.id)|\(.agent)|\(.title)"' 2>/dev/null || true)
    fi
    force_cron_wake "${DIRECTOR_TECH_CRON}" || true
    force_cron_wake "${DIRECTOR_PERSONAL_CRON}" || true
    force_cron_wake "${DIRECTOR_NEGOCIOS_CRON}" || true
  fi

  if (( personal_count > 0 )); then
    report "🚨 Qualidade Notion: ${personal_count} card(s) abertos no Notion Pessoal"
    register_bottleneck "personal-open-backlog" "high" "Backlog aberto no Notion Pessoal" "Há ${personal_count} card(s) OpenClaw em Aguardando/Priorizado/Em andamento no Pessoal." "Forçar cadeia Diretor Pessoal -> especialista e bloquear criação redundante até drenar backlog."
    force_cron_wake "${DIRECTOR_PERSONAL_CRON}" || true
    force_cron_wake "${ENG_PROMPT_CRON}" || true
    force_cron_wake "${MAIL_PERSON_CRON}" || true
  fi

  if (( dup_count > 0 )); then
    report "🚨 Qualidade Notion: ${dup_count} título(s) duplicado(s) abertos no SmartEnvios"
    register_bottleneck "smartenvios-open-duplicates" "critical" "Duplicidade de cards abertos no SmartEnvios" "Foram detectados ${dup_count} títulos duplicados em aberto no SmartEnvios." "Aplicar dedupe por título+fluxo antes de create-card e consolidar card duplicado automaticamente."
    force_cron_wake "${DIRECTOR_TECH_CRON}" || true
    force_cron_wake "${MAIL_PRO_CRON}" || true
    if (( mail_pro_dup > 0 )); then
      report "  • Duplicidade crítica de rotina Mail-Pro detectada (${mail_pro_dup})"
    fi
  fi

  if (( personal_count == 0 && dup_count == 0 && misrouted_eng_prompt == 0 && misrouted_non_tech_directors == 0 )); then
    NOTION_QUALITY_SUMMARY="OK"
    report "✅ Qualidade Notion: sem backlog aberto e sem duplicidades"
  else
    NOTION_QUALITY_SUMMARY="ALERTA (Pessoal=${personal_count},Dup=${dup_count},Roteamento=${misrouted_eng_prompt},DiretoresNoSmart=${misrouted_non_tech_directors})"
  fi
}

audit_pattern_adoption() {
  local audit_raw
  audit_raw=$(python3 - "$PROJECT_ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
issues = []
opportunities = []

patterns_rel = "workspace/templates/agent-behavior-patterns.md"
patterns_path = root / patterns_rel
if not patterns_path.exists():
    issues.append(f"Arquivo ausente: {patterns_rel}")

required_refs = [
    "workspace/FLUXO_AGENTES.md",
    "workspace/agents/eng-prompt/AGENTS.md",
    "workspace/agents/eng-smartenvios/AGENTS.md",
    "workspace/agents/einstein/AGENTS.md",
]

for rel in required_refs:
    p = root / rel
    if not p.exists():
        issues.append(f"Arquivo ausente: {rel}")
        continue
    txt = p.read_text(encoding="utf-8", errors="ignore")
    if "agent-behavior-patterns.md" not in txt:
        issues.append(f"Sem referência ao padrão central em {rel}")

jobs_path = root / "cron/jobs.json"
if not jobs_path.exists():
    issues.append("Arquivo ausente: cron/jobs.json")
else:
    try:
        jobs = json.loads(jobs_path.read_text(encoding="utf-8")).get("jobs", [])
    except Exception:
        jobs = []
        issues.append("Não foi possível ler cron/jobs.json na auditoria de patterns")

    target_names = [
        "Presidente",
        "Diretor Tech",
        "Diretor Pessoal",
        "Diretor Negócios",
        "Engenheiro SmartEnvios",
        "Engenheiro de Prompt",
        "Governança",
    ]
    lifecycle_tokens = ("Aguardando", "Priorizado", "Em andamento", "Concluído")

    for job in jobs:
        name = job.get("name", "")
        if not any(tag in name for tag in target_names):
            continue
        payload = job.get("payload") or {}
        message = payload.get("message") or ""
        lifecycle_hits = sum(token in message for token in lifecycle_tokens)
        if lifecycle_hits >= 2 and "agent-behavior-patterns.md" not in message:
            opportunities.append(
                f"Cron '{name}' replica regras de lifecycle sem link para patterns central"
            )
        lower_msg = message.lower()
        if "notion-helper.sh comment" in message:
            if "4º" not in message and "assinar" not in lower_msg and "assinatura" not in lower_msg:
                opportunities.append(
                    f"Cron '{name}' usa comment Notion sem reforço explícito de assinatura"
                )
        if len(message) > 1700 and "agent-behavior-patterns.md" not in message:
            opportunities.append(
                f"Cron '{name}' tem prompt extenso sem apontar para contrato central"
            )


def emit(tag, items):
    seen = set()
    for item in items:
        line = " ".join(str(item).strip().split())
        if not line or line in seen:
            continue
        seen.add(line)
        print(f"{tag}|{line}")


emit("ISSUE", issues)
emit("OPPORTUNITY", opportunities)
PY
  ) || audit_raw="ISSUE|Falha ao executar auditoria de patterns"

  if [[ -z "${audit_raw//[[:space:]]/}" ]]; then
    report "✅ Auditoria de Patterns: sem desvios e sem novas oportunidades"
    return
  fi

  local has_issues=0
  local has_opportunities=0
  while IFS='|' read -r kind message; do
    [[ -z "${kind:-}" || -z "${message:-}" ]] && continue
    case "$kind" in
      ISSUE)
        if [[ "$has_issues" -eq 0 ]]; then
          report ""
          report "🚨 Auditoria de Patterns — desvios de adoção:"
          has_issues=1
        fi
        report "  • ${message}"
        ;;
      OPPORTUNITY)
        if [[ "$has_opportunities" -eq 0 ]]; then
          report ""
          report "⚠️ Auditoria de Patterns — oportunidades de padronização:"
          has_opportunities=1
        fi
        report "  • ${message}"
        ;;
    esac
  done <<< "$audit_raw"

  if [[ "$has_issues" -eq 1 || "$has_opportunities" -eq 1 ]]; then
    report "  Ação: criar/atualizar card no Notion PESSOAL para Engenheiro de Prompt com os achados."
    register_bottleneck "patterns-adoption-drift" "medium" "Desvios/oportunidades no patterns central" "Auditoria identificou gaps de adoção e/ou oportunidades de padronização entre agentes/crons." "Atualizar prompts e contratos de agente para consumir o patterns central e reduzir divergência operacional."
  fi
}

run_mcp_governance_audit() {
  local audit_script="${PROJECT_ROOT}/workspace/scripts/mcp-governance-audit.sh"
  if [[ ! -x "${audit_script}" ]]; then
    report "⚠️ MCP audit: script ausente (${audit_script})"
    register_bottleneck "mcp-audit-script-missing" "high" "Script de auditoria MCP ausente" "Governança não encontrou o script de auditoria Jira/Grafana via MCP." "Restaurar workspace/scripts/mcp-governance-audit.sh e manter execução em toda rodada."
    return
  fi

  local audit_output audit_status audit_report audit_fails audit_card
  audit_output="$("${audit_script}" --auto-notion 2>/dev/null || true)"
  audit_status="$(echo "${audit_output}" | awk -F= '/^MCP_AUDIT_STATUS=/{print $2}' | tail -n 1)"
  audit_report="$(echo "${audit_output}" | awk -F= '/^MCP_AUDIT_REPORT=/{print $2}' | tail -n 1)"
  audit_fails="$(echo "${audit_output}" | awk -F= '/^MCP_AUDIT_FAIL_COUNT=/{print $2}' | tail -n 1)"
  audit_card="$(echo "${audit_output}" | awk -F= '/^MCP_AUDIT_CARD_ID=/{print $2}' | tail -n 1)"

  [[ ! "${audit_fails}" =~ ^[0-9]+$ ]] && audit_fails=0
  if [[ "${audit_status}" == "ok" && "${audit_fails}" -eq 0 ]]; then
    report "✅ MCP audit (Jira/Grafana): saudável"
  elif [[ -n "${audit_status}" ]]; then
    report "⚠️ MCP audit (Jira/Grafana): ${audit_status} (falhas=${audit_fails})"
    if [[ -n "${audit_card}" ]]; then
      report "📌 MCP audit: card automático criado/atualizado para Diretor Tech (${audit_card})"
    fi
    register_bottleneck "mcp-audit-degraded" "high" "Falhas operacionais no MCP (Jira/Grafana)" "Auditoria automática detectou ${audit_fails} falha(s) no MCP. Relatório: ${audit_report:-indisponível}" "Corrigir integração no repositório /var/www/mcp (auth/permissão/handler) e validar nova rodada automática."
  else
    report "⚠️ MCP audit: sem retorno estruturado (timeout/falha de execução)"
    register_bottleneck "mcp-audit-timeout" "high" "Auditoria MCP sem retorno estruturado" "A etapa de auditoria MCP excedeu timeout ou falhou antes de gerar status." "Revisar tempo de execução e robustez de workspace/scripts/mcp-governance-audit.sh."
  fi
}

audit_mail_scripts_contract() {
  local workflow="${PROJECT_ROOT}/workspace/scripts/gmail/process-workflow.sh"
  local runner="${PROJECT_ROOT}/workspace/scripts/gmail/process-notion-cards.sh"
  local ok=1

  if [[ ! -f "$workflow" ]]; then
    report "🚨 Contrato Mail: arquivo ausente ${workflow}"
    ok=0
  else
    if ! rg -q "mark-read" "$workflow"; then
      report "🚨 Contrato Mail: process-workflow sem ação mark-read"
      ok=0
    fi
    if ! rg -q "archive" "$workflow"; then
      report "🚨 Contrato Mail: process-workflow sem ação archive"
      ok=0
    fi
  fi

  if [[ ! -f "$runner" ]]; then
    report "🚨 Contrato Mail: arquivo ausente ${runner}"
    ok=0
  else
    if ! rg -q "process-workflow.sh" "$runner"; then
      report "🚨 Contrato Mail: process-notion-cards não chama process-workflow.sh"
      ok=0
    fi
    if ! rg -q '"\$\{NOTION_HELPER\}" query|NOTION_HELPER.*query|query "\$\{DB_ID\}"' "$runner"; then
      report "🚨 Contrato Mail: process-notion-cards sem query no Notion"
      ok=0
    fi
  fi

  if [[ "$ok" -eq 1 ]]; then
    report "✅ Contrato Mail: scripts com mark-read + archive + fluxo unificado"
  else
    register_bottleneck "mail-contract-drift" "high" "Drift no contrato da esteira Mail" "Validação do contrato Mail detectou ausência de marcação lido/arquivo ou quebra no fluxo unificado." "Corrigir scripts da esteira Mail e adicionar teste de regressão de contrato."
  fi
}

enforce_critical_cron_contract() {
  local repo_jobs="${PROJECT_ROOT}/cron/jobs.json"
  if [[ ! -f "$repo_jobs" ]]; then
    report "🚨 Contrato de cron: arquivo cron/jobs.json ausente"
    return
  fi

  local drift
  drift=$(python3 - "$repo_jobs" "$CRON_JSON" <<'PY'
import json
import sys

repo_path = sys.argv[1]
try:
    runtime = json.loads(sys.argv[2])
except Exception:
    runtime = {"jobs": []}

try:
    with open(repo_path, encoding="utf-8") as f:
        repo = json.load(f)
except Exception:
    print("ERROR|repo_parse")
    sys.exit(0)

repo_jobs = {j.get("id"): j for j in repo.get("jobs", []) if j.get("id")}
run_jobs = {j.get("id"): j for j in runtime.get("jobs", []) if j.get("id")}

critical = [
    "8c232f9a-b4aa-485f-83c8-99d348bb3176",  # Presidente
    "9da1331a-2c84-4191-9e7d-87552039d8f1",  # Diretor Tech
    "dd8959b6-0346-487f-8281-591249c8dc31",  # Diretor Pessoal
    "12c33196-2e0e-4ce9-b616-98652b7db3ac",  # Diretor Negócios
    "ae4a0347-2e03-46ad-8595-6b9476c45d79",  # Mail-Pro
    "27f27813-12d5-4c2d-a66b-7a50d75b2e98",  # Mail-Person
]

# Frequência fixa obrigatória para evitar duplicidade de execução de e-mail.
schedule_guard = {
    "ae4a0347-2e03-46ad-8595-6b9476c45d79",
    "27f27813-12d5-4c2d-a66b-7a50d75b2e98",
}

semantic = {
    "8c232f9a-b4aa-485f-83c8-99d348bb3176": [
        "Diretor Tech",
        "Tech legado",
        "Aguardando OpenClaw 'Diretor Tech'",
    ],
    "9da1331a-2c84-4191-9e7d-87552039d8f1": [
        "update-agent",
        "Tech legado",
        "Comentário de triagem OBRIGATÓRIO",
    ],
    "dd8959b6-0346-487f-8281-591249c8dc31": [
        "Comentário de triagem OBRIGATÓRIO",
    ],
    "12c33196-2e0e-4ce9-b616-98652b7db3ac": [
        "Comentário de triagem OBRIGATÓRIO",
    ],
    "ae4a0347-2e03-46ad-8595-6b9476c45d79": [
        "process-notion-cards.sh pro 15",
        "stdout literal",
    ],
    "27f27813-12d5-4c2d-a66b-7a50d75b2e98": [
        "process-notion-cards.sh personal 15",
        "stdout literal",
    ],
}

for cron_id in critical:
    expected = repo_jobs.get(cron_id)
    runtime_job = run_jobs.get(cron_id)
    if not expected:
        print(f"MISSING_REPO|{cron_id}|")
        continue
    if not runtime_job:
        print(f"MISSING_RUNTIME|{cron_id}|{expected.get('name', '?')}")
        continue

    cron_name = expected.get("name", "?")

    if cron_id in schedule_guard:
        expected_every = (expected.get("schedule") or {}).get("everyMs")
        runtime_every = (runtime_job.get("schedule") or {}).get("everyMs")
        if expected_every != runtime_every:
            print(f"DRIFT_EVERY|{cron_id}|{cron_name}|{expected_every}|{runtime_every}")

    expected_session = expected.get("sessionTarget") or ""
    runtime_session = runtime_job.get("sessionTarget") or ""
    if expected_session and expected_session != runtime_session:
        print(f"DRIFT_SESSION|{cron_id}|{cron_name}|{expected_session}|{runtime_session}")

    expected_msg = ((expected.get("payload") or {}).get("message") or "")
    runtime_msg = ((runtime_job.get("payload") or {}).get("message") or "")
    if expected_msg != runtime_msg:
        print(f"DRIFT_MESSAGE|{cron_id}|{cron_name}|{len(expected_msg)}|{len(runtime_msg)}")

    for token in semantic.get(cron_id, []):
        if token and token not in runtime_msg:
            print(f"MISSING_TOKEN|{cron_id}|{cron_name}|{token}")
PY
  )

  if [[ -z "${drift//[[:space:]]/}" ]]; then
    report "✅ Contrato crítico de crons: sem drift"
    return
  fi

  if [[ "${drift}" == *"ERROR|"* ]]; then
    report "🚨 Contrato crítico de crons: falha ao comparar runtime vs cron/jobs.json"
    register_bottleneck "cron-contract-compare-failure" "high" "Falha ao validar contrato crítico dos crons" "Comparação entre runtime e cron/jobs.json falhou." "Revisar integridade do arquivo cron/jobs.json e disponibilidade do gateway cron list."
    return
  fi

  # Simplificando - removendo lógica de arrays associativos para compatibilidade
  # Em vez de trackear sync por cron, apenas reportamos todos os drifts
  local changed=0
  local drift_count
  drift_count="$(printf '%s\n' "$drift" | grep -c '.' 2>/dev/null || echo 0)"
  register_bottleneck "cron-contract-drift" "high" "Drift no contrato crítico de crons" "Foram detectados ${drift_count} desvios entre runtime e cron/jobs.json." "Consolidar contrato único dos crons críticos e cobrir com auditoria automática de drift."

  while IFS='|' read -r kind cron_id cron_name a b; do
    [[ -z "${kind:-}" ]] && continue
    case "$kind" in
      MISSING_RUNTIME)
        report "🚨 Contrato de cron: job crítico ausente no runtime (${cron_name}, ${cron_id})"
        ;;
      DRIFT_EVERY)
        if [[ "${a:-0}" =~ ^[0-9]+$ && "$a" -gt 0 ]]; then
          local mins=$((a / 60000))
          if openclaw cron edit "$cron_id" --every "${mins}m" >/dev/null 2>&1; then
            report "🛠️ Contrato de cron: frequência corrigida (${cron_name}: ${b} -> ${a})"
            changed=$((changed + 1))
          else
            report "⚠️ Contrato de cron: falha ao corrigir frequência de ${cron_name}"
          fi
        fi
        ;;
      DRIFT_SESSION)
        if [[ -n "${a:-}" ]]; then
          if openclaw cron edit "$cron_id" --session "$a" >/dev/null 2>&1; then
            report "🛠️ Contrato de cron: sessionTarget corrigido (${cron_name}: ${b} -> ${a})"
            changed=$((changed + 1))
          else
            report "⚠️ Contrato de cron: falha ao corrigir sessionTarget de ${cron_name}"
          fi
        fi
        ;;
      DRIFT_MESSAGE|MISSING_TOKEN)
        local msg
        msg=$(jq -r --arg id "$cron_id" '.jobs[] | select(.id==$id) | .payload.message // empty' "$repo_jobs")
        if [[ -n "${msg:-}" ]]; then
          if openclaw cron edit "$cron_id" --message "$msg" >/dev/null 2>&1; then
            report "🛠️ Contrato de cron: prompt sincronizado (${cron_name})"
            changed=$((changed + 1))
          else
            report "⚠️ Contrato de cron: falha ao sincronizar prompt de ${cron_name}"
          fi
        else
          report "⚠️ Contrato de cron: prompt esperado vazio para ${cron_name}"
        fi
        ;;
      MISSING_REPO)
        report "⚠️ Contrato de cron: ID crítico sem definição no arquivo (${cron_id})"
        ;;
    esac
  done <<< "$drift"

  if [[ "$changed" -gt 0 ]]; then
    CRON_JSON=$(openclaw cron list --json 2>/dev/null || echo '{"jobs":[]}')
    register_bottleneck "cron-contract-autofix" "medium" "Autocorreção recorrente de contrato de cron" "Governança aplicou ${changed} correções automáticas de contrato nesta rodada." "Eliminar a origem do drift para não depender de autocorreções frequentes."
  fi
}

enforce_president_heartbeat_language() {
  local runs_file
  runs_file="${OPENCLAW_CONFIG_DIR}/cron/runs/${PRESIDENT_CRON}.jsonl"
  if [[ ! -f "${runs_file}" ]]; then
    runs_file="${PROJECT_ROOT}/cron/runs/${PRESIDENT_CRON}.jsonl"
  fi
  [[ -f "${runs_file}" ]] || return 0

  local check_result
  check_result="$(python3 - "${runs_file}" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("ok|0||")
    sys.exit(0)

lines = [ln for ln in path.read_text(encoding="utf-8", errors="ignore").splitlines() if ln.strip()]
last = lines[-8:]
en_markers = re.compile(r"\b(the|since|cannot|i will|i need|nothing needs attention|gateway timeout)\b", re.I)
pt_markers = re.compile(r"\b(status|acao|pr[oó]ximo passo|backlog|falhas|custo|executado|conclu[ií]do|governan[çc]a)\b", re.I)
violations = 0
session_key = ""
sample = ""

for raw in last:
    try:
        item = json.loads(raw)
    except Exception:
        continue
    summary = str(item.get("summary") or "")
    if not summary:
        continue
    has_en = bool(en_markers.search(summary))
    has_pt = bool(pt_markers.search(summary))
    if has_en and not has_pt:
        violations += 1
        session_key = str(item.get("sessionKey") or session_key)
        if not sample:
            sample = summary[:180].replace("\n", " ")

print(f"{'drift' if violations > 0 else 'ok'}|{violations}|{session_key}|{sample}")
PY
)"

  local status count session_key sample
  status="${check_result%%|*}"
  count="$(echo "${check_result}" | cut -d'|' -f2)"
  session_key="$(echo "${check_result}" | cut -d'|' -f3)"
  sample="$(echo "${check_result}" | cut -d'|' -f4-)"
  [[ ! "${count}" =~ ^[0-9]+$ ]] && count=0

  if [[ "${status}" != "drift" ]]; then
    report "✅ Idioma heartbeat (Presidente): conforme (pt-BR)"
    return 0
  fi

  report "🚨 Idioma heartbeat (Presidente): detectado desvio para inglês (${count} ocorrência(s) recentes)"
  register_bottleneck "president-heartbeat-language-drift" "high" "Presidente respondeu heartbeat fora de pt-BR" "Foram detectadas ${count} ocorrências recentes de resumo em inglês. Exemplo: ${sample}" "Forçar prompt determinístico em pt-BR, resetar sessão do cron do Presidente e validar próximas rodadas."

  local strict_msg
  strict_msg="MODO DETERMINISTICO OBRIGATORIO: execute exatamente este comando em foreground e sem process/background: ./scripts/president-mail-demand-cycle.sh. Responda somente com o JSON retornado pelo comando (sem texto adicional). Idioma obrigatório pt-BR."

  if openclaw cron edit "${PRESIDENT_CRON}" --message "${strict_msg}" >/dev/null 2>&1; then
    report "🛠️ Presidente: prompt de heartbeat reforçado para saída estrita em pt-BR"
  else
    report "⚠️ Presidente: falha ao reforçar prompt do cron"
  fi

  if [[ -n "${session_key:-}" ]]; then
    if openclaw sessions reset "${session_key}" --yes >/dev/null 2>&1; then
      report "🧹 Presidente: sessão de cron resetada para eliminar contexto contaminado"
    fi
  fi

  force_cron_wake "${PRESIDENT_CRON}" || true
}

enforce_main_heartbeat_language() {
  local sessions_dir
  sessions_dir="${OPENCLAW_CONFIG_DIR}/agents/main/sessions"
  if [[ ! -d "${sessions_dir}" ]]; then
    sessions_dir="${PROJECT_ROOT}/agents/main/sessions"
  fi
  [[ -d "${sessions_dir}" ]] || return 0

  local check_result
  check_result="$(python3 - "${sessions_dir}" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
files = sorted(root.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
if not files:
    print("ok|0|")
    raise SystemExit(0)

target = files[0]
raw_lines = target.read_text(encoding="utf-8", errors="ignore").splitlines()[-220:]
en_markers = re.compile(r"\b(the|since|cannot|i will|i need|nothing needs attention|gateway timeout|checked the cron jobs)\b", re.I)
pt_markers = re.compile(r"\b(status|ação|proximo passo|próximo passo|falhas|backlog|governan[çc]a|executado|conclu[ií]do)\b", re.I)
heartbeat_markers = re.compile(r"heartbeat|HEARTBEAT_OK|nothing needs attention|HEARTBEAT\.md", re.I)
violations = 0
sample = ""

for ln in raw_lines:
    try:
        obj = json.loads(ln)
    except Exception:
        continue
    msg = obj.get("message") or {}
    if msg.get("role") != "assistant":
        continue
    text_parts = []
    content = msg.get("content") or []
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text_parts.append(str(item.get("text") or ""))
    text = "\n".join(text_parts).strip()
    if not text:
        continue
    if not heartbeat_markers.search(text):
        continue
    has_en = bool(en_markers.search(text))
    has_pt = bool(pt_markers.search(text))
    if has_en and not has_pt:
        violations += 1
        if not sample:
            sample = text[:180].replace("\n", " ")

print(f"{'drift' if violations > 0 else 'ok'}|{violations}|{sample}")
PY
)"

  local status count sample
  status="${check_result%%|*}"
  count="$(echo "${check_result}" | cut -d'|' -f2)"
  sample="$(echo "${check_result}" | cut -d'|' -f3-)"
  [[ ! "${count}" =~ ^[0-9]+$ ]] && count=0

  if [[ "${status}" != "drift" ]]; then
    report "✅ Idioma heartbeat (main): conforme (pt-BR)"
    return 0
  fi

  report "🚨 Idioma heartbeat (main): desvio para inglês (${count} ocorrência(s))"
  register_bottleneck "main-heartbeat-language-drift" "high" "Main respondeu heartbeat fora de pt-BR" "Detectadas ${count} ocorrências recentes no agent:main:main. Exemplo: ${sample}" "Resetar sessão main e reforçar HEARTBEAT.md para saída binária (HEARTBEAT_OK/ALERTA)."

  if openclaw sessions reset "agent:main:main" --yes >/dev/null 2>&1; then
    report "🧹 Main: sessão agent:main:main resetada após desvio de idioma"
  fi
}

audit_recent_triage_comments() {
  local api_key="$1"
  local db_id="$2"
  local label="$3"
  local director="$4"
  [[ -z "${api_key:-}" || -z "${db_id:-}" || -z "${director:-}" ]] && return

  local missing
  missing=$(python3 - "$api_key" "$db_id" "$director" <<'PY'
import datetime
import json
import sys
import urllib.parse
import urllib.request

api_key, db_id, director = sys.argv[1], sys.argv[2], sys.argv[3]
headers = {
    "Authorization": f"Bearer {api_key}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}

query_body = json.dumps({
    "filter": {
        "and": [
            {"property": "Status", "select": {"equals": "Priorizado"}},
            {"property": "Tipo", "select": {"equals": "OpenClaw"}}
        ]
    },
    "sorts": [{"timestamp": "last_edited_time", "direction": "descending"}],
    "page_size": 8
}).encode()

try:
    req = urllib.request.Request(
        f"https://api.notion.com/v1/databases/{db_id}/query",
        data=query_body,
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))
except Exception:
    print("ERROR|query")
    sys.exit(0)

now = datetime.datetime.now(datetime.timezone.utc)
signature = f"[{director}]".lower()

for page in data.get("results", []):
    edited = page.get("last_edited_time")
    if not edited:
        continue
    try:
        edited_dt = datetime.datetime.fromisoformat(edited.replace("Z", "+00:00"))
    except Exception:
        continue
    age_min = (now - edited_dt).total_seconds() / 60
    if age_min > 180:
        continue

    page_id = page.get("id", "")
    title = ""
    for prop in page.get("properties", {}).values():
        if prop.get("type") == "title":
            title = "".join(t.get("plain_text", "") for t in prop.get("title", []))
            break

    normalized_title = " ".join((title or "").lower().split())
    if normalized_title.startswith("[governança][melhoria]") or normalized_title.startswith("[governanca][melhoria]"):
        # Card técnico criado automaticamente pela governança, sem necessidade de comentário do diretor.
        continue

    comments_text = ""
    next_cursor = None
    for _ in range(2):
        url = f"https://api.notion.com/v1/comments?block_id={urllib.parse.quote(page_id)}"
        if next_cursor:
            url += f"&start_cursor={urllib.parse.quote(next_cursor)}"
        try:
            creq = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(creq, timeout=20) as cresp:
                cdata = json.loads(cresp.read().decode("utf-8"))
        except Exception:
            break
        for comment in cdata.get("results", []):
            comments_text += " " + "".join(rt.get("plain_text", "") for rt in comment.get("rich_text", []))
        if not cdata.get("has_more"):
            break
        next_cursor = cdata.get("next_cursor")

    if signature not in comments_text.lower():
        print(f"{page_id}|{title[:90]}|{int(age_min)}")
PY
  )

  [[ -z "${missing//[[:space:]]/}" ]] && return
  if [[ "${missing}" == *"ERROR|"* ]]; then
    report "⚠️ [${label}] Não foi possível auditar comentários de triagem no Notion"
    register_bottleneck "triage-signature-audit-error-${label}" "medium" "Falha ao auditar assinatura de triagem (${label})" "Auditoria de comentários do diretor não pôde ser concluída no Notion ${label}." "Reforçar robustez da auditoria e adicionar retry/fallback para leitura de comentários."
    return
  fi

  report ""
  report "⚠️ [${label}] Cards Priorizado recentes sem assinatura de triagem [${director}]:"
  register_bottleneck "triage-signature-missing-${label}" "medium" "Cards Priorizado sem comentário do diretor (${label})" "Há cards Priorizado recentes sem assinatura [${director}] de triagem." "Reforçar contrato de triagem do diretor com comentário obrigatório e validação automática."
  while IFS='|' read -r page_id title mins; do
    [[ -z "${page_id:-}" ]] && continue
    report "  • ${title} (${mins}min, id=${page_id})"
  done <<< "$missing"
}

audit_mail_card_consistency() {
  local api_key="$1"
  local db_id="$2"
  local label="$3"
  [[ -z "${api_key:-}" || -z "${db_id:-}" ]] && return

  local findings
  findings=$(python3 - "$api_key" "$db_id" <<'PY'
import json
import re
import sys
import urllib.parse
import urllib.request
from collections import Counter

api_key, db_id = sys.argv[1], sys.argv[2]
headers = {
    "Authorization": f"Bearer {api_key}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}

def plain_text(rich):
    return "".join((x or {}).get("plain_text", "") for x in (rich or []))

def normalize_text(s):
    return " ".join((s or "").strip().lower().split())

def request_json(req):
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))

try:
    query_body = json.dumps({
        "filter": {
            "and": [
                {"property": "Tipo", "select": {"equals": "OpenClaw"}},
                {"or": [
                    {"property": "Status", "select": {"equals": "Aguardando"}},
                    {"property": "Status", "select": {"equals": "Priorizado"}},
                    {"property": "Status", "select": {"equals": "Em andamento"}}
                ]}
            ]
        },
        "sorts": [{"timestamp": "last_edited_time", "direction": "descending"}],
        "page_size": 10
    }).encode()
    req = urllib.request.Request(
        f"https://api.notion.com/v1/databases/{db_id}/query",
        data=query_body,
        headers=headers,
        method="POST",
    )
    data = request_json(req)
except Exception:
    print("ERROR|query")
    sys.exit(0)

for page in data.get("results", []):
    page_id = page.get("id", "")
    props = page.get("properties", {})
    title = ""
    for prop in props.values():
        if prop.get("type") == "title":
            title = "".join(t.get("plain_text", "") for t in prop.get("title", []))
            break

    title_lower = normalize_text(title)
    if "mail-pro" not in title_lower and "mail-person" not in title_lower:
        continue

    # 1) Conteúdo do corpo: duplicação e drift (limite fixo 100).
    body_lines = []
    headings = []
    try:
        breq = urllib.request.Request(
            f"https://api.notion.com/v1/blocks/{urllib.parse.quote(page_id)}/children?page_size=100",
            headers=headers,
            method="GET",
        )
        bdata = request_json(breq)
    except Exception:
        bdata = {"results": []}

    for block in bdata.get("results", []):
        btype = block.get("type", "")
        content = block.get(btype, {}) if btype else {}
        text = plain_text(content.get("rich_text"))
        if not text:
            continue
        body_lines.append(text)
        if btype in {"heading_1", "heading_2", "heading_3"}:
            headings.append(normalize_text(text))

    body_text = "\n".join(body_lines)
    body_norm = normalize_text(body_text)

    # Indica descrição inchada/duplicada de rotina.
    for target in ("objetivo", "escopo", "critérios de conclusão"):
        count = sum(1 for h in headings if h == target)
        if count >= 2:
            print(f"ISSUE|{page_id}|{title[:90]}|Seção duplicada no corpo: '{target}' aparece {count}x")

    if len(body_text) > 6500:
        print(f"ISSUE|{page_id}|{title[:90]}|Corpo muito extenso ({len(body_text)} chars) — provável duplicação de descrição")

    if re.search(r"(até\\s*100|ate\\s*100|limite\\s*[:=]?\\s*100|processar\\s*até\\s*100)", body_norm):
        print(f"ISSUE|{page_id}|{title[:90]}|Descrição desatualizada cita limite fixo de 100 e-mails")

    # 2) Comentários repetidos do Presidente (spam de acompanhamento).
    comments = []
    next_cursor = None
    for _ in range(3):
        url = f"https://api.notion.com/v1/comments?block_id={urllib.parse.quote(page_id)}"
        if next_cursor:
            url += f"&start_cursor={urllib.parse.quote(next_cursor)}"
        try:
            creq = urllib.request.Request(url, headers=headers, method="GET")
            cdata = request_json(creq)
        except Exception:
            break
        for comment in cdata.get("results", []):
            text = plain_text(comment.get("rich_text"))
            if text:
                comments.append(text)
        if not cdata.get("has_more"):
            break
        next_cursor = cdata.get("next_cursor")

    president_msgs = []
    for c in comments:
        cl = c.strip()
        if cl.lower().startswith("[presidente]"):
            msg = normalize_text(cl[len("[Presidente]"):])
            if msg:
                president_msgs.append(msg)

    if president_msgs:
        freq = Counter(president_msgs)
        msg, count = freq.most_common(1)[0]
        if count >= 3:
            snippet = (msg[:85] + "...") if len(msg) > 85 else msg
            print(f"ISSUE|{page_id}|{title[:90]}|Comentário repetitivo do Presidente ({count}x): '{snippet}'")
PY
  ) || findings="ERROR|exec"

  if [[ -z "${findings//[[:space:]]/}" ]]; then
    report "✅ [${label}] Consistência dos cards Mail: sem drift de corpo/comentários"
    return
  fi
  if [[ "${findings}" == *"ERROR|"* ]]; then
    report "⚠️ [${label}] Não foi possível auditar consistência de cards Mail"
    return
  fi

  report ""
  report "⚠️ [${label}] Auditoria de consistência dos cards Mail:"
  register_bottleneck "mail-card-consistency-${label}" "medium" "Inconsistência nos cards Mail (${label})" "Auditoria detectou drift de corpo/comentários em cards Mail ${label}." "Padronizar template de card/comentário e aplicar anti-duplicação de conteúdo."
  while IFS='|' read -r kind page_id title detail; do
    [[ -z "${kind:-}" || -z "${page_id:-}" ]] && continue
    report "  • ${title} (id=${page_id}): ${detail}"
  done <<< "$findings"
  report "  Ação: atualizar prompt/regras para evitar duplicação de corpo e spam de comentários."
}

audit_recent_concluded_without_evidence() {
  local api_key="$1"
  local db_id="$2"
  local label="$3"
  local api_key_var="$4"
  [[ -z "${api_key:-}" || -z "${db_id:-}" || -z "${api_key_var:-}" ]] && return

  local weak
  weak=$(python3 - "$api_key" "$db_id" "${GOV_CONCLUDED_AUDIT_WINDOW_MIN}" "${GOV_CONCLUDED_AUDIT_LIMIT}" <<'PY'
import datetime
import json
import sys
import urllib.parse
import urllib.request

api_key, db_id = sys.argv[1], sys.argv[2]
window_min, page_size = int(sys.argv[3]), int(sys.argv[4])
headers = {
    "Authorization": f"Bearer {api_key}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}
now = datetime.datetime.now(datetime.timezone.utc)

query_body = json.dumps({
    "filter": {
        "and": [
            {"property": "Tipo", "select": {"equals": "OpenClaw"}},
            {"property": "Status", "select": {"equals": "Concluído"}}
        ]
    },
    "sorts": [{"timestamp": "last_edited_time", "direction": "descending"}],
    "page_size": page_size
}).encode()

try:
    req = urllib.request.Request(
        f"https://api.notion.com/v1/databases/{db_id}/query",
        data=query_body,
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=25) as resp:
        data = json.loads(resp.read().decode("utf-8"))
except Exception:
    print("ERROR|query")
    sys.exit(0)

evidence_keywords = [
    "resultado executivo",
    "evidência",
    "evidencias",
    "execução real",
    "workflow.sh",
    "process-workflow.sh",
    "arquivos alterados",
    "teste",
    "métricas",
    "status final confirmado",
]

for page in data.get("results", []):
    page_id = page.get("id", "")
    if not page_id:
        continue

    edited = page.get("last_edited_time", "")
    if not edited:
        continue
    try:
        edited_dt = datetime.datetime.fromisoformat(edited.replace("Z", "+00:00"))
    except Exception:
        continue
    age_min = int((now - edited_dt).total_seconds() / 60)
    if age_min > window_min:
        continue

    props = page.get("properties", {})
    title = ""
    for prop in props.values():
        if prop.get("type") == "title":
            title = "".join(t.get("plain_text", "") for t in prop.get("title", []))
            break
    agent = (((props.get("Agente") or {}).get("select") or {}).get("name") or "").strip()
    if not agent:
        continue

    comments_text = []
    next_cursor = None
    for _ in range(3):
        url = f"https://api.notion.com/v1/comments?block_id={urllib.parse.quote(page_id)}"
        if next_cursor:
            url += f"&start_cursor={urllib.parse.quote(next_cursor)}"
        try:
            creq = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(creq, timeout=20) as cresp:
                cdata = json.loads(cresp.read().decode("utf-8"))
        except Exception:
            break
        for comment in cdata.get("results", []):
            text = "".join(rt.get("plain_text", "") for rt in comment.get("rich_text", []))
            if text:
                comments_text.append(text)
        if not cdata.get("has_more"):
            break
        next_cursor = cdata.get("next_cursor")

    joined = " ".join(comments_text).strip().lower()
    if not joined:
        print(f"{page_id}|{agent}|{title[:90]}|sem_comentarios")
        continue

    if "drenagem assistida" in joined:
        if not any(k in joined for k in evidence_keywords):
            print(f"{page_id}|{agent}|{title[:90]}|drenagem_assistida_sem_evidencia")
        continue

    if not any(k in joined for k in evidence_keywords):
        print(f"{page_id}|{agent}|{title[:90]}|sem_evidencia_minima")
PY
  ) || weak="ERROR|exec"

  if [[ -z "${weak//[[:space:]]/}" ]]; then
    report "✅ [${label}] Auditoria de Concluído: sem cards sem evidência mínima"
    return
  fi
  if [[ "${weak}" == *"ERROR|"* ]]; then
    report "⚠️ [${label}] Não foi possível auditar cards Concluído sem evidência"
    register_bottleneck "concluded-audit-error-${label}" "medium" "Falha na auditoria de conclusões (${label})" "Governança não conseguiu auditar cards Concluído recentes sem evidência mínima." "Reforçar robustez da auditoria de comentários Notion (retry/timeout/fallback)."
    return
  fi

  local reopened=0
  report ""
  report "🚨 [${label}] Conclusões sem evidência detectadas:"
  while IFS='|' read -r page_id agent title reason; do
    [[ -z "${page_id:-}" || -z "${agent:-}" ]] && continue
    report "  • ${title} (Agente=${agent}, motivo=${reason}, id=${page_id})"
    if [[ "${reason}" == "drenagem_assistida" ]]; then
      report "    ℹ️ Somente alerta: drenagem assistida detectada com evidência; sem reabertura automática."
      continue
    fi
    if (( reopened >= GOV_CONCLUDED_REOPEN_LIMIT )); then
      continue
    fi
    "${NOTION_HELPER_SCRIPT}" comment "${page_id}" "${api_key_var}" "Governança: card foi marcado como Concluído sem evidência mínima de execução real (${reason}). Reaberto para execução individual pelo agente responsável com evidências objetivas." "Governança" >/dev/null 2>&1 || true
    "${NOTION_HELPER_SCRIPT}" update-status "${page_id}" "${api_key_var}" "Priorizado" >/dev/null 2>&1 || true
    verify="$("${NOTION_HELPER_SCRIPT}" get-page "${page_id}" "${api_key_var}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
    if [[ "${verify}" == "Priorizado" ]]; then
      reopened=$((reopened + 1))
      report "    🔁 Reaberto para Priorizado e wake acionado (Agente=${agent})"
      wake_for_agent "${agent}" "conclusão sem evidência (${label})" || true
      register_bottleneck "weak-conclusion-${label}-${page_id}" "high" "Card concluído sem evidência mínima (${label})" "Card '${title}' foi marcado como Concluído sem evidência objetiva de execução real (motivo=${reason})." "Reabrir para Priorizado, processar 1 card por vez com evidências de comando/resultado e só então concluir."
    fi
  done <<< "$weak"
}

check_legacy_tech_cards() {
  local api_key="$1"
  local db_id="$2"
  [[ -z "${api_key:-}" || -z "${db_id:-}" ]] && return

  local legacy
  legacy=$(curl -sS --connect-timeout 5 --max-time "${GOV_STAGE_TIMEOUT_GENERAL_SEC}" -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{"filter":{"and":[{"property":"Tipo","select":{"equals":"OpenClaw"}},{"property":"Agente","select":{"equals":"Tech"}},{"or":[{"property":"Status","select":{"equals":"Aguardando"}},{"property":"Status","select":{"equals":"Priorizado"}}]}]}}' 2>/dev/null | python3 -c "
import datetime, json, sys
data = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
for page in data.get('results', []):
    page_id = page.get('id', '')
    props = page.get('properties', {})
    status = props.get('Status', {}).get('select', {}).get('name', '')
    edited = page.get('last_edited_time', '')
    mins = 999
    if edited:
        dt = datetime.datetime.fromisoformat(edited.replace('Z', '+00:00'))
        mins = int((now - dt).total_seconds() / 60)
    title = ''
    for prop in props.values():
        if prop.get('type') == 'title':
            title = ''.join(t.get('plain_text', '') for t in prop.get('title', []))
            break
    print(f'{page_id}|{status}|{title[:80]}|{mins}')
" 2>/dev/null || true)

  [[ -z "${legacy//[[:space:]]/}" ]] && return

  report ""
  report "🚨 [Tech] Legado detectado: cards com Agente=Tech no SmartEnvios"
  register_bottleneck "legacy-tech-routing" "medium" "Roteamento legado detectado (Agente=Tech)" "Foram encontrados cards OpenClaw com Agente=Tech no SmartEnvios." "Concluir migração de roteamento legado para Diretor Tech e bloquear regressão no presidente/diretores."
  while IFS='|' read -r page_id status title mins; do
    [[ -z "${page_id:-}" ]] && continue
    report "  • ${title} (Status=${status}, ${mins}min, id=${page_id})"
    if [[ "$status" == "Aguardando" && -x "${NOTION_HELPER_SCRIPT}" ]]; then
      if "${NOTION_HELPER_SCRIPT}" update-agent "$page_id" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" >/dev/null 2>&1; then
        report "    🛠️ Normalizado automaticamente: Agente=Diretor Tech"
      else
        report "    ⚠️ Falha ao normalizar automaticamente para Diretor Tech"
      fi
    fi
  done <<< "$legacy"
}

force_cron_wake() {
  local cron_id="$1"
  [[ -z "${cron_id:-}" ]] && return 0
  # Evita tempestade de wakes no mesmo ciclo.
  if [[ "${WOKEN_CRONS}" == *"|${cron_id}|"* ]]; then
    return 0
  fi
  if (( WAKES_USED >= GOV_WAKE_BUDGET_PER_ROUND )); then
    WAKES_DROPPED=$((WAKES_DROPPED + 1))
    report "🛑 Wake bloqueado por budget (${GOV_WAKE_BUDGET_PER_ROUND}/rodada): cron=${cron_id}"
    register_bottleneck "wake-budget-exceeded-${cron_id}" "high" "Wake bloqueado por budget da governança" "Cron ${cron_id} não recebeu wake nesta rodada por estouro do limite (${GOV_WAKE_BUDGET_PER_ROUND})." "Priorizar wakes por severidade e reduzir fan-out em cascata."
    return 0
  fi
  local can_wake_output can_wake decision reason
  can_wake_output="$(python3 - "${GOV_WAKE_STATE_FILE}" "${cron_id}" "${GOV_WAKE_MIN_GAP_SEC}" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
cron_id = sys.argv[2]
min_gap = int(sys.argv[3])
now = int(time.time())

state = {}
if state_path.exists():
    try:
        raw = json.loads(state_path.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            state = raw
    except Exception:
        state = {}

last = int(state.get(cron_id, 0) or 0)
elapsed = now - last if last > 0 else (min_gap + 1)
if elapsed >= min_gap:
    print("allow|ok")
else:
    print(f"deny|cooldown:{max(1, min_gap - elapsed)}")
PY
)"
  decision="${can_wake_output%%|*}"
  reason="${can_wake_output#*|}"
  if [[ "${decision}" != "allow" ]]; then
    WAKES_DROPPED=$((WAKES_DROPPED + 1))
    report "⏸️ Wake em cooldown: cron=${cron_id} (${reason})"
    return 0
  fi
  WOKEN_CRONS="${WOKEN_CRONS}${cron_id}|"
  WAKES_USED=$((WAKES_USED + 1))
  local direct_ok="false"
  if [[ "${GOV_FORCE_CRON_RUN_ON_RECOVERY}" == "true" ]]; then
    if ocw_cron_wake_now "$cron_id" "${GOV_WAKE_TIMEOUT_MS}" >/dev/null 2>&1 || ocw_cron_run "$cron_id" "${GOV_WAKE_TIMEOUT_MS}" >/dev/null 2>&1; then
      direct_ok="true"
    fi
  else
    if ocw_cron_wake_now "$cron_id" "${GOV_WAKE_TIMEOUT_MS}" >/dev/null 2>&1 || ocw_cron_run "$cron_id" "${GOV_WAKE_TIMEOUT_MS}" >/dev/null 2>&1; then
      direct_ok="true"
    fi
  fi

  if [[ "${direct_ok}" != "true" && "${GOV_USE_SAFE_RUN_FALLBACK}" == "true" && -x "${CRON_SAFE_RUNNER}" ]]; then
    "${CRON_SAFE_RUNNER}" --cycles 1 --ids "${cron_id}" >/dev/null 2>&1 || true
    report "🛟 Fallback recovery: cron-safe-run acionado para ${cron_id}"
  fi
  python3 - "${GOV_WAKE_STATE_FILE}" "${cron_id}" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
cron_id = sys.argv[2]
now = int(time.time())

state = {}
if state_path.exists():
    try:
        raw = json.loads(state_path.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            state = raw
    except Exception:
        state = {}

state[cron_id] = now
state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
PY
  return 0
}

consume_president_force_request() {
  [[ -f "${PRESIDENT_FORCE_FILE}" ]] || return 0

  local requested_at unread_pro unread_personal threshold_pro threshold_personal reason
  local chain_gate chain_decision chain_reason
  requested_at="$(jq -r '.requestedAt // 0' "${PRESIDENT_FORCE_FILE}" 2>/dev/null || echo 0)"
  unread_pro="$(jq -r '.unreadPro // 0' "${PRESIDENT_FORCE_FILE}" 2>/dev/null || echo 0)"
  unread_personal="$(jq -r '.unreadPersonal // 0' "${PRESIDENT_FORCE_FILE}" 2>/dev/null || echo 0)"
  threshold_pro="$(jq -r '.thresholdPro // 0' "${PRESIDENT_FORCE_FILE}" 2>/dev/null || echo 0)"
  threshold_personal="$(jq -r '.thresholdPersonal // 0' "${PRESIDENT_FORCE_FILE}" 2>/dev/null || echo 0)"
  reason="$(jq -r '.reason // "manual"' "${PRESIDENT_FORCE_FILE}" 2>/dev/null || echo "manual")"

  [[ ! "${requested_at}" =~ ^[0-9]+$ ]] && requested_at=0
  [[ ! "${unread_pro}" =~ ^[0-9]+$ ]] && unread_pro=0
  [[ ! "${unread_personal}" =~ ^[0-9]+$ ]] && unread_personal=0
  [[ ! "${threshold_pro}" =~ ^[0-9]+$ ]] && threshold_pro=0
  [[ ! "${threshold_personal}" =~ ^[0-9]+$ ]] && threshold_personal=0

  if (( requested_at > 0 )); then
    local now age_sec
    now="$(date +%s)"
    age_sec=$((now - requested_at))
    if (( age_sec > 3600 )); then
      report "ℹ️ Sinal do Presidente expirado (${age_sec}s); descartando pedido antigo."
      rm -f "${PRESIDENT_FORCE_FILE}" 2>/dev/null || true
      return 0
    fi
  fi

  chain_gate="$(mail_chain_force_gate)"
  chain_decision="${chain_gate%%|*}"
  chain_reason="${chain_gate#*|}"
  if [[ "${chain_decision}" != "allow" ]]; then
    report "⏸️ Sinal do Presidente recebido, mas forçar cadeia está em cooldown (${chain_reason})."
    return 0
  fi

  report "🚨 Sinal do Presidente: forçar execução da cadeia mail (motivo=${reason}, pro=${unread_pro}/${threshold_pro}, pessoal=${unread_personal}/${threshold_personal})"
  force_cron_wake "${DIRECTOR_TECH_CRON}" || true
  force_cron_wake "${DIRECTOR_PERSONAL_CRON}" || true
  force_cron_wake "${MAIL_PRO_CRON}" || true
  force_cron_wake "${MAIL_PERSON_CRON}" || true
  force_cron_wake "${OPTIMIZER_CRON}" || true
  mark_mail_chain_forced
  register_bottleneck "president-force-chain" "high" "Presidente solicitou forçar cadeia de execução" "Backlog elevado sinalizado pelo Presidente (pro=${unread_pro}, pessoal=${unread_personal})." "Drenar backlog em ondas curtas e validar queda sustentada dos não lidos."

  rm -f "${PRESIDENT_FORCE_FILE}" 2>/dev/null || true
}

wake_for_agent() {
  local agent="${1:-}"
  local reason="${2:-recuperação}"
  case "$agent" in
    Mail-Pro)
      force_cron_wake "${MAIL_PRO_CRON}"
      report "🔄 Wake enviado para cron Mail-Pro (${reason})"
      return 0
      ;;
    Mail-Person)
      force_cron_wake "${MAIL_PERSON_CRON}"
      report "🔄 Wake enviado para cron Mail-Person (${reason})"
      return 0
      ;;
    "Engenheiro de Prompt")
      force_cron_wake "${ENG_PROMPT_CRON}"
      report "🔄 Wake enviado para cron Engenheiro de Prompt (${reason})"
      return 0
      ;;
    "Engenheiro SmartEnvios")
      force_cron_wake "${ENG_SMARTENVIOS_CRON}"
      report "🔄 Wake enviado para cron Engenheiro SmartEnvios (${reason})"
      return 0
      ;;
    "Especialista de Suporte de Software")
      force_cron_wake "${ESP_SUPORTE_SOFTWARE_CRON}"
      report "🔄 Wake enviado para cron Especialista de Suporte de Software (${reason})"
      return 0
      ;;
    "Diretor Tech")
      force_cron_wake "${DIRECTOR_TECH_CRON}"
      report "🔄 Wake enviado para cron Diretor Tech (${reason})"
      return 0
      ;;
    "Diretor Pessoal")
      force_cron_wake "${DIRECTOR_PERSONAL_CRON}"
      report "🔄 Wake enviado para cron Diretor Pessoal (${reason})"
      return 0
      ;;
    "Diretor Negócios")
      force_cron_wake "${DIRECTOR_NEGOCIOS_CRON}"
      report "🔄 Wake enviado para cron Diretor Negócios (${reason})"
      return 0
      ;;
    Presidente)
      force_cron_wake "${PRESIDENT_CRON}"
      report "🔄 Wake enviado para cron Presidente (${reason})"
      return 0
      ;;
  esac
  return 1
}

recover_stuck_eng_prompt_card() {
  [[ -x "${NOTION_HELPER_SCRIPT}" ]] || return 0
  [[ -n "${NOTION_PERSONAL_API_KEY:-}" ]] || return 0

  local row page_id title mins target_status verify_status
  row="$(NOTION_CACHE_ENABLED=false "${NOTION_HELPER_SCRIPT}" query "${NOTION_PERSONAL_DB_ID}" NOTION_PERSONAL_API_KEY "Engenheiro de Prompt" "Em andamento" "Em andamento" 2>/dev/null | python3 - "${GOV_ENG_PROMPT_STUCK_MIN}" <<'PY'
import datetime
import json
import sys

threshold = int(sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc)
raw = sys.stdin.read()
if not raw.strip():
    print("")
    raise SystemExit(0)
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)
rows = []
for page in data.get("results", []):
    edited = page.get("last_edited_time", "")
    mins = 999
    if edited:
        dt = datetime.datetime.fromisoformat(edited.replace("Z", "+00:00"))
        mins = int((now - dt).total_seconds() / 60)
    if mins < threshold:
        continue
    title = ""
    props = page.get("properties", {})
    try:
        title = props["Name"]["title"][0].get("plain_text", "")
    except Exception:
        title = "(sem título)"
    rows.append((mins, page.get("id", ""), title[:120]))
rows.sort(key=lambda x: x[0], reverse=True)
if rows:
    mins, page_id, title = rows[0]
    print(f"{page_id}|{title}|{mins}")
PY
)" || row=""

  [[ -z "${row//[[:space:]]/}" ]] && return 0

  IFS='|' read -r page_id title mins <<< "${row}"
  [[ -z "${page_id:-}" ]] && return 0

  target_status="Priorizado"
  if [[ "${mins}" =~ ^[0-9]+$ ]] && (( mins >= GOV_ENG_PROMPT_IMPEDIMENTO_MIN )); then
    target_status="Impedimento"
  fi

  "${NOTION_HELPER_SCRIPT}" comment "${page_id}" NOTION_PERSONAL_API_KEY "Governança detectou execução travada em Em andamento há ${mins}min. Movendo para ${target_status} para destravar o fluxo com recuperação controlada." "Governança" >/dev/null 2>&1 || true
  "${NOTION_HELPER_SCRIPT}" update-status "${page_id}" NOTION_PERSONAL_API_KEY "${target_status}" >/dev/null 2>&1 || true
  verify_status="$("${NOTION_HELPER_SCRIPT}" get-page "${page_id}" NOTION_PERSONAL_API_KEY | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"

  if [[ "${verify_status}" == "${target_status}" ]]; then
    report "🧯 [Pessoal] Recuperação Eng. Prompt: card travado '${title}' (${mins}min) -> ${target_status}"
    register_bottleneck "eng-prompt-stuck-recovered-${page_id}" "high" "Recuperação de card travado (Eng. Prompt)" "Governança recuperou card '${title}' após ${mins}min em Em andamento, movendo para ${target_status}." "Manter ciclo determinístico com validação de status e fallback automático para evitar travamentos prolongados."
    wake_for_agent "Engenheiro de Prompt" "recuperação de travamento"
  else
    report "⚠️ [Pessoal] Falha ao recuperar card travado do Eng. Prompt: '${title}' (id=${page_id})"
    register_bottleneck "eng-prompt-stuck-recovery-failed-${page_id}" "critical" "Falha na recuperação de card travado (Eng. Prompt)" "Card '${title}' permaneceu travado; status não confirmou transição para ${target_status}." "Revisar integração Notion do especialista e garantir atualização transacional com verificação pós-write."
  fi
}

recover_stuck_eng_smartenvios_card() {
  [[ -x "${NOTION_HELPER_SCRIPT}" ]] || return 0
  [[ -n "${NOTION_SMARTENVIOS_API_KEY:-}" ]] || return 0

  local row page_id title mins verify_status
  row="$(NOTION_CACHE_ENABLED=false "${NOTION_HELPER_SCRIPT}" query "adec12e735dc41a3bb7c274b287f3a10" NOTION_SMARTENVIOS_API_KEY "Engenheiro SmartEnvios" "Em andamento" "Em andamento" 2>/dev/null | python3 - "${GOV_ENG_SMART_STUCK_MIN}" <<'PY'
import datetime
import json
import sys

threshold = int(sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc)
raw = sys.stdin.read()
if not raw.strip():
    print("")
    raise SystemExit(0)
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

rows = []
for page in data.get("results", []):
    edited = page.get("last_edited_time", "")
    mins = 999
    if edited:
        dt = datetime.datetime.fromisoformat(edited.replace("Z", "+00:00"))
        mins = int((now - dt).total_seconds() / 60)
    if mins < threshold:
        continue
    title = ""
    props = page.get("properties", {})
    try:
        title = props["Name"]["title"][0].get("plain_text", "")
    except Exception:
        title = "(sem título)"
    rows.append((mins, page.get("id", ""), title[:120]))

rows.sort(key=lambda x: x[0], reverse=True)
if rows:
    mins, page_id, title = rows[0]
    print(f"{page_id}|{title}|{mins}")
PY
)" || row=""

  [[ -z "${row//[[:space:]]/}" ]] && return 0
  IFS='|' read -r page_id title mins <<< "${row}"
  [[ -z "${page_id:-}" ]] && return 0

  "${NOTION_HELPER_SCRIPT}" comment "${page_id}" NOTION_SMARTENVIOS_API_KEY "Governança detectou card travado em Em andamento há ${mins}min. Retornando para Priorizado para reprocessamento determinístico do Engenheiro SmartEnvios." "Governança" >/dev/null 2>&1 || true
  "${NOTION_HELPER_SCRIPT}" update-status "${page_id}" NOTION_SMARTENVIOS_API_KEY "Priorizado" >/dev/null 2>&1 || true
  verify_status="$("${NOTION_HELPER_SCRIPT}" get-page "${page_id}" NOTION_SMARTENVIOS_API_KEY | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"

  if [[ "${verify_status}" == "Priorizado" ]]; then
    report "🧯 [Tech] Recuperação Eng. SmartEnvios: card travado '${title}' (${mins}min) -> Priorizado"
    register_bottleneck "eng-smart-stuck-recovered-${page_id}" "high" "Recuperação de card travado (Eng. SmartEnvios)" "Governança recuperou card '${title}' após ${mins}min em Em andamento, movendo para Priorizado." "Garantir execução determinística do Engenheiro SmartEnvios com validação de status e timeout de etapa."
    wake_for_agent "Engenheiro SmartEnvios" "recuperação de travamento"
  else
    report "⚠️ [Tech] Falha ao recuperar card travado do Eng. SmartEnvios: '${title}' (id=${page_id})"
    register_bottleneck "eng-smart-stuck-recovery-failed-${page_id}" "critical" "Falha na recuperação de card travado (Eng. SmartEnvios)" "Card '${title}' permaneceu travado; status não confirmou retorno para Priorizado." "Revisar integração Notion do especialista e aplicar fallback transacional com verificação pós-write."
  fi
}

recover_paused_cards() {
  [[ -x "${NOTION_HELPER_SCRIPT}" ]] || return 0
  local max_cards="${GOV_PAUSED_RECOVERY_LIMIT:-2}"
  [[ "${max_cards}" =~ ^[0-9]+$ ]] || max_cards=2
  (( max_cards > 0 )) || return 0

  local db_entries=(
    "${NOTION_PERSONAL_API_KEY:-}|${NOTION_PERSONAL_DB_ID}|Pessoal|NOTION_PERSONAL_API_KEY"
    "${NOTION_SMARTENVIOS_API_KEY:-}|adec12e735dc41a3bb7c274b287f3a10|Tech|NOTION_SMARTENVIOS_API_KEY"
  )

  local recovered=0
  local entry api_key db_id label api_var paused_rows

  for entry in "${db_entries[@]}"; do
    IFS='|' read -r api_key db_id label api_var <<< "${entry}"
    [[ -n "${api_key:-}" ]] || continue
    (( recovered >= max_cards )) && break

    paused_rows="$(curl -sS --connect-timeout 5 --max-time "${GOV_STAGE_TIMEOUT_GENERAL_SEC}" -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
      -H "Authorization: Bearer ${api_key}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{"filter":{"and":[{"property":"Tipo","select":{"equals":"OpenClaw"}},{"property":"Status","select":{"equals":"Pausado"}}]}}' 2>/dev/null | python3 - <<'PY'
import datetime
import json
import sys

now = datetime.datetime.now(datetime.timezone.utc)
data = json.load(sys.stdin)
rows = []
for page in data.get("results", []):
    page_id = page.get("id", "")
    if not page_id:
        continue
    props = page.get("properties", {})
    title = ""
    try:
        title = props["Name"]["title"][0].get("plain_text", "")
    except Exception:
        title = "(sem título)"
    agent = ""
    try:
        agent = (props.get("Agente", {}).get("select") or {}).get("name", "")
    except Exception:
        agent = ""
    edited = page.get("last_edited_time", "")
    mins = 0
    if edited:
        dt = datetime.datetime.fromisoformat(edited.replace("Z", "+00:00"))
        mins = int((now - dt).total_seconds() / 60)
    rows.append((mins, page_id, title[:120], agent))

rows.sort(key=lambda x: x[0], reverse=True)
for mins, pid, title, agent in rows:
    print(f"{pid}|{title}|{agent}|{mins}")
PY
)" || paused_rows=""

    [[ -n "${paused_rows//[[:space:]]/}" ]] || continue
    while IFS='|' read -r page_id title agent mins; do
      [[ -n "${page_id:-}" ]] || continue
      (( recovered >= max_cards )) && break

      "${NOTION_HELPER_SCRIPT}" comment "${page_id}" "${api_var}" "Governança: card encontrado em Pausado (${mins}min). Retornando para Priorizado para retomada automática do fluxo." "Governança" >/dev/null 2>&1 || true
      "${NOTION_HELPER_SCRIPT}" update-status "${page_id}" "${api_var}" "Priorizado" >/dev/null 2>&1 || true

      local verify_status
      verify_status="$("${NOTION_HELPER_SCRIPT}" get-page "${page_id}" "${api_var}" | jq -r '.properties.Status.select.name // ""' 2>/dev/null || true)"
      if [[ "${verify_status}" == "Priorizado" ]]; then
        recovered=$((recovered + 1))
        report "🧯 [${label}] Card Pausado recuperado: '${title}' -> Priorizado (Agente=${agent:-sem-agente})"
        register_bottleneck "notion-paused-recovered-${label}-${page_id}" "high" "Card Pausado recuperado (${label})" "Card '${title}' estava em Pausado e foi reativado para Priorizado automaticamente." "Eliminar causa raiz que move cards para Pausado sem retomada e manter wake automático do agente responsável."
        if [[ -n "${agent:-}" ]]; then
          wake_for_agent "${agent}" "recuperação de pausado" || true
        fi
      else
        report "⚠️ [${label}] Falha ao recuperar card Pausado: '${title}' (id=${page_id})"
      fi
    done <<< "${paused_rows}"
  done

  if (( recovered == 0 )); then
    report "✅ Recuperação de Pausado: nenhum card elegível nesta rodada"
  fi
}

rebind_critical_cron_ids_from_runtime() {
  [[ -z "${CRON_JSON:-}" ]] && return 0

  local bindings
  bindings="$(python3 - "${CRON_JSON}" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {"jobs": []}

jobs = data.get("jobs", []) or []

rules = {
    "PRESIDENT_CRON": ["Presidente - criar demandas"],
    "DIRECTOR_TECH_CRON": ["Diretor Tech - varredura"],
    "DIRECTOR_PERSONAL_CRON": ["Diretor Pessoal - varredura"],
    "DIRECTOR_NEGOCIOS_CRON": ["Diretor Negócios - varredura"],
    "MAIL_PRO_CRON": ["Mail-Pro especialista - execução"],
    "MAIL_PERSON_CRON": ["Mail-Person especialista - execução"],
}

for key, patterns in rules.items():
    picked = None
    for p in patterns:
        for j in jobs:
            name = str(j.get("name") or "")
            if p in name:
                picked = (str(j.get("id") or ""), name)
                break
        if picked:
            break
    if picked and picked[0]:
        print(f"{key}|{picked[0]}|{picked[1]}")
PY
)"

  [[ -z "${bindings}" ]] && return 0
  while IFS='|' read -r var_name found_id found_name; do
    [[ -z "${var_name}" || -z "${found_id}" ]] && continue
    local current_id=""
    current_id="$(eval "printf '%s' \"\${${var_name}:-}\"")"
    if [[ "${current_id}" != "${found_id}" ]]; then
      eval "${var_name}='${found_id}'"
      report "🧭 Rebinding automático de cron: ${var_name} -> ${found_id} (${found_name})"
      register_bottleneck "cron-id-rebind-${var_name}" "medium" "Cron ID rebinding automático" "Governança atualizou ${var_name} para ${found_id} (${found_name}) por drift de ID." "Sincronizar IDs críticos no script com a configuração ativa para evitar wake em cron inexistente."
    fi
  done <<< "${bindings}"
}

prune_overflow_cron_sessions() {
  # Reset oversized cron sessions (context overflow) to restore autonomy and reduce waste/cost.
  local st
  st="$(openclaw status --json --timeout 5000 2>/dev/null || true)"
  [[ -z "${st}" ]] && return 0

  local offenders
  offenders="$(
    printf '%s' "${st}" | python3 -c '
import json, sys
threshold = int(sys.argv[1])
data = json.load(sys.stdin)
recent = ((data.get("sessions") or {}).get("recent") or [])
for s in recent:
    key = s.get("key") or ""
    pct = int(s.get("percentUsed") or 0)
    kind = s.get("kind") or ""
    if kind != "direct":
        continue
    if ":cron:" not in key:
        continue
    if pct >= threshold:
        print(f"{key}|{pct}|{s.get(\"model\",\"?\")}|{int(s.get(\"age\") or 0)}")
' "${GOV_SESSION_OVERFLOW_PCT}" 2>/dev/null || true
  )"

  [[ -z "${offenders}" ]] && return 0
  report "⚠️ Sessões de cron com overflow detectadas (>=${GOV_SESSION_OVERFLOW_PCT}%) — resetando"
  while IFS='|' read -r key pct model age_ms; do
    [[ -z "${key:-}" ]] && continue
    log "Reset de sessão overflow: ${key} (${pct}%, model=${model})"
    ocw_sessions_reset "${key}" >/dev/null 2>&1 || true
    register_bottleneck "session-overflow-${key//[^a-zA-Z0-9]/_}" "medium" \
      "Sessão de cron com overflow (reset aplicada)" \
      "Sessão ${key} estava com ${pct}% de contexto (model=${model}). Governança aplicou reset para recuperar execução." \
      "Reduzir contexto/prompt do cron, mover regras para patterns central, e limitar payload do cron para evitar compaction/timeout."
  done <<< "${offenders}"
}

check_mail_processing_locks() {
  local now profile lock_dir pid_file ts_file pid created_at age_min reason pid_cmd label
  now="$(date +%s)"
  for profile in pro personal; do
    lock_dir="/tmp/openclaw-mail-${profile}.lockdir"
    [[ -d "${lock_dir}" ]] || continue

    pid_file="${lock_dir}/pid"
    ts_file="${lock_dir}/created_at"
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    created_at="$(cat "${ts_file}" 2>/dev/null || echo 0)"
    age_min=0
    if [[ "${created_at}" =~ ^[0-9]+$ ]] && (( created_at > 0 )) && (( now >= created_at )); then
      age_min=$(( (now - created_at) / 60 ))
    fi

    reason=""
    if [[ ! "${pid}" =~ ^[0-9]+$ ]]; then
      reason="pid-ausente-ou-invalido"
    elif ! kill -0 "${pid}" 2>/dev/null; then
      reason="processo-inexistente"
    else
      pid_cmd="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
      if [[ "${pid_cmd}" != *"process-notion-cards.sh"* ]]; then
        reason="pid-reutilizado"
      fi
    fi

    label="Mail-Pro"
    [[ "${profile}" == "personal" ]] && label="Mail-Person"

    if [[ -n "${reason}" ]]; then
      rm -rf "${lock_dir}" 2>/dev/null || true
      report "🧹 Lock órfão removido (${label}): ${reason}, idade=${age_min}min"
      register_bottleneck "mail-lock-orphan-${profile}" "high" "Lock órfão detectado no ${label}" "Lock ${lock_dir} removido automaticamente (${reason}, idade=${age_min}min)." "Garantir lock com PID e autocura no pipeline de e-mail; revisar contenção de execução paralela."
      continue
    fi

    if (( age_min >= 30 )); then
      report "⚠️ Lock ativo por muito tempo (${label}): ${age_min}min (PID=${pid})"
      register_bottleneck "mail-lock-long-${profile}" "high" "Lock prolongado no ${label}" "Lock ${lock_dir} ativo há ${age_min}min (PID=${pid})." "Investigar stuck process no workflow de e-mail e reduzir timeout/carga por rodada."
    fi
  done
}

audit_mail_cron_contention() {
  local entries=(
    "${MAIL_PRO_CRON}|Mail-Pro|pro"
    "${MAIL_PERSON_CRON}|Mail-Person|personal"
  )
  local item cron_id label profile run_file contention_count
  for item in "${entries[@]}"; do
    IFS='|' read -r cron_id label profile <<< "${item}"
    run_file="${OPENCLAW_CONFIG_DIR}/cron/runs/${cron_id}.jsonl"
    [[ -f "${run_file}" ]] || continue
    contention_count="$(tail -n 140 "${run_file}" 2>/dev/null | grep -c 'execucao-ja-em-andamento' || true)"
    [[ ! "${contention_count}" =~ ^[0-9]+$ ]] && contention_count=0
    if (( contention_count >= 3 )); then
      report "⚠️ Contenção detectada no ${label}: ${contention_count} ocorrências recentes de execucao-ja-em-andamento"
      register_bottleneck "mail-contention-${profile}" "high" "Contenção recorrente no ${label}" "${contention_count} ocorrências recentes de 'execucao-ja-em-andamento' no log do cron." "Revisar janela/frequência/timeout e garantir lock idempotente com saneamento de órfãos."
    fi
  done
}

can_trigger_optimizer_now() {
  local min_gap_ms="${1:-7200000}"  # 2h
  local result
  result=$(python3 - "$CRON_JSON" "$OPTIMIZER_CRON" "$min_gap_ms" <<'PY'
import json
import sys
import time

raw, cron_id, min_gap = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    data = json.loads(raw)
except Exception:
    print("yes")
    sys.exit(0)

job = next((j for j in data.get("jobs", []) if j.get("id") == cron_id), None)
if not job:
    print("no")
    sys.exit(0)

state = job.get("state") or {}
last = state.get("lastRunAtMs") or 0
now = int(time.time() * 1000)
print("yes" if (last <= 0 or (now - last) >= min_gap) else "no")
PY
  )
  [[ "${result}" == "yes" ]]
}

mail_chain_force_gate() {
  python3 - "${GOV_MAIL_CHAIN_STATE_FILE}" "${GOV_MAIL_CHAIN_FORCE_COOLDOWN_SEC}" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
cooldown = int(sys.argv[2])
now = int(time.time())
last = 0
if state_path.exists():
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
        if isinstance(state, dict):
            last = int(state.get("lastForcedAt", 0) or 0)
    except Exception:
        last = 0
elapsed = (now - last) if last > 0 else (cooldown + 1)
if elapsed >= cooldown:
    print("allow|ok")
else:
    print(f"deny|cooldown:{max(1, cooldown - elapsed)}")
PY
}

# Avalia saúde operacional por resultados reais (backlog, crons em erro, cards travados).
# Não confundir com "cron rodou" — aqui importa se os papéis estão sendo cumpridos.
compute_operational_health() {
  local issues="" status="OK"
  local unread_pro=0 unread_personal=0
  local backlog_alert="${GOV_OPERATIONAL_BACKLOG_ALERT:-40}"
  local backlog_critical="${GOV_OPERATIONAL_BACKLOG_CRITICAL:-60}"
  local critical_count=0 high_count=0

  [[ "${backlog_alert}" =~ ^[0-9]+$ ]] || backlog_alert=40
  [[ "${backlog_critical}" =~ ^[0-9]+$ ]] || backlog_critical=60

  # Backlog de e-mail (resultado real do Mail-Pro / Mail-Person)
  if [[ -x "${GMAIL_SCRIPT}" ]]; then
    unread_pro="$("${GMAIL_SCRIPT}" pro list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
    unread_personal="$("${GMAIL_SCRIPT}" personal list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
    [[ ! "${unread_pro}" =~ ^[0-9]+$ ]] && unread_pro=0
    [[ ! "${unread_personal}" =~ ^[0-9]+$ ]] && unread_personal=0
    if (( unread_pro >= backlog_critical )); then
      issues="${issues}\n  • E-mail pro: ${unread_pro} não lidos (limiar crítico ${backlog_critical})"
      status="CRÍTICO"
    elif (( unread_pro >= backlog_alert )); then
      issues="${issues}\n  • E-mail pro: ${unread_pro} não lidos (acima do limiar ${backlog_alert})"
      [[ "${status}" != "CRÍTICO" ]] && status="ALERTA"
    fi
    if (( unread_personal >= backlog_critical )); then
      issues="${issues}\n  • E-mail pessoal: ${unread_personal} não lidos (limiar crítico ${backlog_critical})"
      status="CRÍTICO"
    elif (( unread_personal >= backlog_alert )); then
      issues="${issues}\n  • E-mail pessoal: ${unread_personal} não lidos (acima do limiar ${backlog_alert})"
      [[ "${status}" != "CRÍTICO" ]] && status="ALERTA"
    fi
  fi

  # Crons críticos em erro de execução (lastRunStatus = execução; lastStatus = compatibilidade com gateway < 2026.2.22)
  local key_crons="${PRESIDENT_CRON}|Presidente,${MAIL_PRO_CRON}|Mail-Pro,${MAIL_PERSON_CRON}|Mail-Person,${ENG_PROMPT_CRON}|Eng. de Prompt,${ENG_SMARTENVIOS_CRON}|Eng. SmartEnvios,${ESP_SUPORTE_SOFTWARE_CRON}|Esp. Suporte Software"
  local cron_errors
  cron_errors="$(echo "$CRON_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
key_list = sys.argv[1].split(',')
for pair in key_list:
    cid, label = pair.split('|', 1)
    for j in data.get('jobs', []):
        if j.get('id') == cid:
            st = (j.get('state') or {})
            # Prefer lastRunStatus (2026.2.22+), fallback to lastStatus for older gateway
            run_status = (st.get('lastRunStatus') or st.get('lastStatus') or '').lower()
            if run_status == 'error':
                err = (st.get('lastError') or '')[:80]
                print(f\"{label}|{err}\")
            break
" "${key_crons}" 2>/dev/null || true)"
  if [[ -n "${cron_errors}" ]]; then
    while IFS='|' read -r label err; do
      [[ -z "${label}" ]] && continue
      issues="${issues}\n  • Cron ${label} em erro (última execução)"
      status="CRÍTICO"
    done <<< "${cron_errors}"
  fi

  # Qualidade Notion (auditoria de duplicados/roteamento)
  if [[ "${NOTION_QUALITY_SUMMARY}" != "OK" ]]; then
    issues="${issues}\n  • Notion: ${NOTION_QUALITY_SUMMARY}"
    [[ "${status}" != "CRÍTICO" ]] && status="ALERTA"
  fi

  # Gargalos críticos/high desta rodada
  if [[ -s "${BOTTLENECK_EVENTS_FILE}" ]]; then
    critical_count="$(grep -c '"severity":"critical"' "${BOTTLENECK_EVENTS_FILE}" 2>/dev/null || echo 0)"
    high_count="$(grep -c '"severity":"high"' "${BOTTLENECK_EVENTS_FILE}" 2>/dev/null || echo 0)"
    [[ ! "${critical_count}" =~ ^[0-9]+$ ]] && critical_count=0
    [[ ! "${high_count}" =~ ^[0-9]+$ ]] && high_count=0
    if (( critical_count > 0 )); then
      issues="${issues}\n  • ${critical_count} gargalo(s) crítico(s) registrado(s) nesta rodada"
      status="CRÍTICO"
    fi
    if (( high_count > 0 )) && [[ "${status}" != "CRÍTICO" ]]; then
      issues="${issues}\n  • ${high_count} gargalo(s) de alta prioridade nesta rodada"
      status="ALERTA"
    fi
  fi

  # Cards travados ou Priorizado abandonado (resultado real dos especialistas / Presidente)
  if [[ -s "${NOTION_RECOVERY_CANDIDATES_FILE:-}" ]]; then
    local stuck_count priorizado_count
    stuck_count="$(grep -c '|stuck|' "${NOTION_RECOVERY_CANDIDATES_FILE}" 2>/dev/null || echo 0)"
    priorizado_count="$(grep -c '|priorizado|' "${NOTION_RECOVERY_CANDIDATES_FILE}" 2>/dev/null || echo 0)"
    [[ ! "${stuck_count}" =~ ^[0-9]+$ ]] && stuck_count=0
    [[ ! "${priorizado_count}" =~ ^[0-9]+$ ]] && priorizado_count=0
    if (( stuck_count > 0 )); then
      issues="${issues}\n  • ${stuck_count} card(s) Em andamento travado(s) (especialista sem progresso)"
      status="CRÍTICO"
    fi
    if (( priorizado_count > 0 )) && [[ "${status}" != "CRÍTICO" ]]; then
      issues="${issues}\n  • ${priorizado_count} card(s) Priorizado abandonado(s) (sem execução)"
      status="ALERTA"
    fi
  fi

  OPERATIONAL_HEALTH_STATUS="${status}"
  OPERATIONAL_HEALTH_ISSUES="${issues}"
}

mark_mail_chain_forced() {
  python3 - "${GOV_MAIL_CHAIN_STATE_FILE}" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
state_path.parent.mkdir(parents=True, exist_ok=True)
state = {"lastForcedAt": int(time.time())}
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
PY
}

guard_mail_backlogs() {
  local unread_pro unread_personal
  local active_pro active_personal
  local threshold="${MAIL_BACKLOG_OVERLOAD_THRESHOLD:-80}"
  local create_threshold_pro="${MAIL_BACKLOG_CREATE_THRESHOLD_PRO:-20}"
  local create_threshold_personal="${MAIL_BACKLOG_CREATE_THRESHOLD_PERSONAL:-5}"
  local overload=0
  local create_triggered=0
  local chain_gate chain_decision chain_reason chain_forced_this_round=0

  [[ ! "${threshold}" =~ ^[0-9]+$ ]] && threshold=80
  [[ ! "${create_threshold_pro}" =~ ^[0-9]+$ ]] && create_threshold_pro=20
  [[ ! "${create_threshold_personal}" =~ ^[0-9]+$ ]] && create_threshold_personal=5
  chain_gate="$(mail_chain_force_gate)"
  chain_decision="${chain_gate%%|*}"
  chain_reason="${chain_gate#*|}"

  if [[ ! -x "${GMAIL_SCRIPT}" || ! -x "${NOTION_HELPER_SCRIPT}" ]]; then
    report "⚠️ Backlog e-mail: scripts Gmail/Notion indisponíveis para auditoria"
    register_bottleneck "mail-backlog-audit-unavailable" "medium" "Auditoria de backlog indisponível" "Scripts Gmail/Notion ausentes para checagem de backlog." "Validar presença/permissão dos scripts e garantir fallback operacional."
    return
  fi

  unread_pro="$("${GMAIL_SCRIPT}" pro list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
  unread_personal="$("${GMAIL_SCRIPT}" personal list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
  [[ ! "${unread_pro}" =~ ^[0-9]+$ ]] && unread_pro=0
  [[ ! "${unread_personal}" =~ ^[0-9]+$ ]] && unread_personal=0

  report "📬 Backlog e-mail: Pro=${unread_pro} | Personal=${unread_personal} (não lidos)"

  active_pro="$("${NOTION_HELPER_SCRIPT}" query adec12e735dc41a3bb7c274b287f3a10 NOTION_SMARTENVIOS_API_KEY "Mail-Pro" Priorizado "Em andamento" 2>/dev/null | jq -r '.results | length' 2>/dev/null || echo 0)"
  active_personal="$("${NOTION_HELPER_SCRIPT}" query bfcbe7a7a3a745489e605e0762af12a9 NOTION_PERSONAL_API_KEY "Mail-Person" Priorizado "Em andamento" 2>/dev/null | jq -r '.results | length' 2>/dev/null || echo 0)"
  [[ ! "${active_pro}" =~ ^[0-9]+$ ]] && active_pro=0
  [[ ! "${active_personal}" =~ ^[0-9]+$ ]] && active_personal=0

  # Nível 1: criação de demanda (baixo) — força Presidente quando existe backlog
  # e não há card ativo do especialista.
  if (( unread_pro >= create_threshold_pro )) && (( active_pro == 0 )); then
    create_triggered=1
    if [[ "${chain_decision}" == "allow" && ${chain_forced_this_round} -eq 0 ]]; then
      report "🧭 Mail-Pro sem card ativo com backlog >= ${create_threshold_pro}: forçando Presidente -> Diretor Tech -> Mail-Pro"
      force_cron_wake "${PRESIDENT_CRON}" || true
      force_cron_wake "${DIRECTOR_TECH_CRON}" || true
      force_cron_wake "${MAIL_PRO_CRON}" || true
      chain_forced_this_round=1
      mark_mail_chain_forced
    else
      report "⏸️ Forçar cadeia Mail-Pro em cooldown (${chain_reason})"
    fi
  fi

  if (( unread_personal >= create_threshold_personal )) && (( active_personal == 0 )); then
    create_triggered=1
    if [[ "${chain_decision}" == "allow" && ${chain_forced_this_round} -eq 0 ]]; then
      report "🧭 Mail-Person sem card ativo com backlog >= ${create_threshold_personal}: forçando Presidente -> Diretor Pessoal -> Mail-Person"
      force_cron_wake "${PRESIDENT_CRON}" || true
      force_cron_wake "${DIRECTOR_PERSONAL_CRON}" || true
      force_cron_wake "${MAIL_PERSON_CRON}" || true
      chain_forced_this_round=1
      mark_mail_chain_forced
    else
      report "⏸️ Forçar cadeia Mail-Person em cooldown (${chain_reason})"
    fi
  fi

  if (( unread_pro >= threshold )); then
    overload=1
    report "🚨 Mail-Pro backlog alto: ${unread_pro} não lidos"
    register_bottleneck "mail-backlog-pro" "high" "Backlog alto no Mail-Pro" "Mail-Pro com ${unread_pro} não lidos (cards ativos: ${active_pro})." "Ajustar lote/frequência e eliminar contenção por lock para reduzir backlog de forma sustentada."
    if (( active_pro == 0 )); then
      if [[ "${chain_decision}" == "allow" && ${chain_forced_this_round} -eq 0 ]]; then
        report "  Ação: sem card ativo Mail-Pro, forçando cadeia Presidente -> Diretor Tech -> Mail-Pro"
        force_cron_wake "${PRESIDENT_CRON}" || true
        force_cron_wake "${DIRECTOR_TECH_CRON}" || true
        force_cron_wake "${MAIL_PRO_CRON}" || true
        chain_forced_this_round=1
        mark_mail_chain_forced
      else
        report "  Ação: cadeia Mail-Pro em cooldown (${chain_reason}); sem fan-out nesta rodada"
      fi
    else
      report "  Ação: ${active_pro} card(s) ativo(s) Mail-Pro; forçando execução imediata do Mail-Pro"
      force_cron_wake "${MAIL_PRO_CRON}" || true
    fi
  fi

  if (( unread_personal >= threshold )); then
    overload=1
    report "🚨 Mail-Person backlog alto: ${unread_personal} não lidos"
    register_bottleneck "mail-backlog-personal" "high" "Backlog alto no Mail-Person" "Mail-Person com ${unread_personal} não lidos (cards ativos: ${active_personal})." "Ajustar lote/frequência e eliminar contenção por lock para reduzir backlog de forma sustentada."
    if (( active_personal == 0 )); then
      if [[ "${chain_decision}" == "allow" && ${chain_forced_this_round} -eq 0 ]]; then
        report "  Ação: sem card ativo Mail-Person, forçando cadeia Presidente -> Diretor Pessoal -> Mail-Person"
        force_cron_wake "${PRESIDENT_CRON}" || true
        force_cron_wake "${DIRECTOR_PERSONAL_CRON}" || true
        force_cron_wake "${MAIL_PERSON_CRON}" || true
        chain_forced_this_round=1
        mark_mail_chain_forced
      else
        report "  Ação: cadeia Mail-Person em cooldown (${chain_reason}); sem fan-out nesta rodada"
      fi
    else
      report "  Ação: ${active_personal} card(s) ativo(s) Mail-Person; forçando execução imediata do Mail-Person"
      force_cron_wake "${MAIL_PERSON_CRON}" || true
    fi
  fi

  if (( overload == 1 )); then
    if can_trigger_optimizer_now 7200000; then
      force_cron_wake "${OPTIMIZER_CRON}" || true
      report "🛠️ Trigger Otimizador: backlog alto detectado, execução do cron Otimizador acionada"
    else
      report "ℹ️ Trigger Otimizador: backlog alto detectado, mas Otimizador já rodou recentemente (<2h)"
    fi
  else
    report "✅ Backlog e-mail: sem sobrecarga acima do limite (${threshold})"
  fi

  if (( create_triggered == 1 )) && (( overload == 0 )); then
    report "📝 Backlog com auto-criação ativada: Presidente forçado para criação de demanda mesmo sem sobrecarga crítica."
  fi
}

drain_notion_backlog_by_agent() {
  local db_id="$1"
  local api_key="$2"
  local label="$3"
  [[ -z "${db_id}" || -z "${api_key}" ]] && return 0

  local rows
  rows="$(curl -sS --connect-timeout 5 --max-time "${GOV_STAGE_TIMEOUT_GENERAL_SEC}" -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{"filter":{"and":[{"property":"Tipo","select":{"equals":"OpenClaw"}},{"or":[{"property":"Status","select":{"equals":"Aguardando"}},{"property":"Status","select":{"equals":"Priorizado"}}]}]}}' 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
counts = {}
for page in data.get('results', []):
    props = page.get('properties', {})
    agent = (((props.get('Agente') or {}).get('select') or {}).get('name') or '').strip()
    status = (((props.get('Status') or {}).get('select') or {}).get('name') or '').strip()
    if not agent:
        continue
    key = (agent, status)
    counts[key] = counts.get(key, 0) + 1
for (agent, status), qty in sorted(counts.items()):
    print(f'{agent}|{status}|{qty}')
" 2>/dev/null || true)"

  [[ -z "${rows}" ]] && return 0
  local seen=""
  while IFS='|' read -r agent status qty; do
    [[ -z "${agent}" ]] && continue
    if [[ "${seen}" != *"|${agent}|"* ]]; then
      seen="${seen}|${agent}|"
      if wake_for_agent "${agent}" "drenagem backlog ${label}"; then
        report "📦 Drenagem ${label}: ${agent} com backlog (Aguardando/Priorizado)"
      fi
    fi
  done <<< "${rows}"
}

guard_daily_ai_costs() {
  local runs_dir cost_json
  local total_brl total_usd total_tokens unpriced_tokens
  local top_model_line top_job_line over_alert over_critical severity

  runs_dir="${OPENCLAW_CONFIG_DIR}/cron/runs"
  if [[ ! -d "${runs_dir}" ]]; then
    runs_dir="${PROJECT_ROOT}/cron/runs"
  fi
  if [[ ! -d "${runs_dir}" ]]; then
    report "⚠️ Custo IA: diretório de execuções não encontrado (${OPENCLAW_CONFIG_DIR}/cron/runs)"
    register_bottleneck "ai-cost-runs-missing" "medium" "Auditoria de custo indisponível" "Diretório de runs não encontrado para calcular custo diário." "Garantir persistência dos runs em cron/runs para observabilidade de custo."
    return
  fi

  cost_json="$(python3 - "${runs_dir}" "${CRON_JSON}" "${GOV_COST_USD_BRL}" <<'PY'
import datetime
import json
import sys
from collections import defaultdict
from pathlib import Path
from zoneinfo import ZoneInfo

runs_dir = Path(sys.argv[1])
try:
    cron_data = json.loads(sys.argv[2])
except Exception:
    cron_data = {"jobs": []}
usd_brl = float(sys.argv[3])

job_names = {
    str(j.get("id") or ""): str(j.get("name") or "?")
    for j in (cron_data.get("jobs") or [])
}

# Pricing aproximado (OpenRouter) para modelos observados no ambiente.
# Unidade: USD por token.
pricing = {
    "google/gemini-3-pro-preview": (0.000002, 0.000012),
    "gemini-3-pro-preview": (0.000002, 0.000012),
    "google/gemini-2.5-pro": (0.00000125, 0.00001),
    "gemini-2.5-pro": (0.00000125, 0.00001),
    "google/gemini-2.5-flash": (0.0000003, 0.0000025),
    "gemini-2.5-flash": (0.0000003, 0.0000025),
    "google/gemini-2.5-flash-lite": (0.0000001, 0.0000004),
    "gemini-2.5-flash-lite": (0.0000001, 0.0000004),
    "google/gemini-2.0-flash-001": (0.0000001, 0.0000004),
    "gemini-2.0-flash-001": (0.0000001, 0.0000004),
    "deepseek/deepseek-chat": (0.00000032, 0.00000089),
    "deepseek-chat": (0.00000032, 0.00000089),
    "deepseek/deepseek-chat-v3.1": (0.00000015, 0.00000075),
    "deepseek-chat-v3.1": (0.00000015, 0.00000075),
    "openai/gpt-4-turbo": (0.00001, 0.00003),
    "gpt-4-turbo": (0.00001, 0.00003),
    "openai/gpt-5.1-codex": (0.00000125, 0.00001),
    "gpt-5.1-codex": (0.00000125, 0.00001),
    "x-ai/grok-3-mini": (0.0000003, 0.0000005),
    "xai/grok-3-mini": (0.0000003, 0.0000005),
    "grok-3-mini": (0.0000003, 0.0000005),
    "anthropic/claude-sonnet-4.6": (0.000003, 0.000015),
    "anthropic/claude-sonnet-4-6": (0.000003, 0.000015),
    "claude-sonnet-4-6": (0.000003, 0.000015),
}

def model_rates(model: str):
    raw = (model or "").strip().lower()
    candidates = [raw]
    if "/" in raw:
        candidates.append(raw.split("/", 1)[1])
    if raw.startswith("xai/"):
        candidates.append(raw.replace("xai/", "x-ai/", 1))
    if raw.startswith("x-ai/"):
        candidates.append(raw.replace("x-ai/", "xai/", 1))
    candidates.append(raw.replace("-4-6", "-4.6"))
    for key in candidates:
        if key in pricing:
            return pricing[key]
    return (0.0, 0.0)

start_sp = datetime.datetime.now(ZoneInfo("America/Sao_Paulo")).replace(hour=0, minute=0, second=0, microsecond=0)
cut_ms = int(start_sp.timestamp() * 1000)

total_input = 0
total_output = 0
total_usd = 0.0
unpriced_tokens = 0
cost_by_model = defaultdict(float)
tokens_by_model = defaultdict(int)
cost_by_job = defaultdict(float)
tokens_by_job = defaultdict(int)

for run_file in sorted(runs_dir.glob("*.jsonl")):
    job_id = run_file.stem
    try:
        lines = run_file.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        continue
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except Exception:
            continue
        ts = int(item.get("ts") or 0)
        if ts < cut_ms:
            continue
        usage = item.get("usage") or {}
        if not isinstance(usage, dict):
            continue
        input_tokens = int(usage.get("input_tokens") or 0)
        output_tokens = int(usage.get("output_tokens") or 0)
        if input_tokens <= 0 and output_tokens <= 0:
            continue

        model = str(item.get("model") or "unknown")
        pr_in, pr_out = model_rates(model)
        cost = (input_tokens * pr_in) + (output_tokens * pr_out)
        if pr_in == 0.0 and pr_out == 0.0:
            unpriced_tokens += input_tokens + output_tokens

        total_input += input_tokens
        total_output += output_tokens
        total_usd += cost

        model_key = model.strip() or "unknown"
        cost_by_model[model_key] += cost
        tokens_by_model[model_key] += input_tokens + output_tokens
        cost_by_job[job_id] += cost
        tokens_by_job[job_id] += input_tokens + output_tokens

top_models = [
    {"model": m, "costUsd": round(c, 4), "tokens": int(tokens_by_model[m])}
    for m, c in sorted(cost_by_model.items(), key=lambda kv: kv[1], reverse=True)[:3]
]
top_jobs = [
    {
        "jobId": j,
        "name": job_names.get(j, j),
        "costUsd": round(c, 4),
        "tokens": int(tokens_by_job[j]),
    }
    for j, c in sorted(cost_by_job.items(), key=lambda kv: kv[1], reverse=True)[:3]
]

total_brl = total_usd * usd_brl
out = {
    "totalUsd": round(total_usd, 4),
    "totalBrl": round(total_brl, 2),
    "totalInput": total_input,
    "totalOutput": total_output,
    "totalTokens": total_input + total_output,
    "unpricedTokens": unpriced_tokens,
    "topModels": top_models,
    "topJobs": top_jobs,
}
print(json.dumps(out, ensure_ascii=False))
PY
)"

  total_brl="$(echo "${cost_json}" | jq -r '.totalBrl // 0' 2>/dev/null || echo 0)"
  total_usd="$(echo "${cost_json}" | jq -r '.totalUsd // 0' 2>/dev/null || echo 0)"
  total_tokens="$(echo "${cost_json}" | jq -r '.totalTokens // 0' 2>/dev/null || echo 0)"
  unpriced_tokens="$(echo "${cost_json}" | jq -r '.unpricedTokens // 0' 2>/dev/null || echo 0)"
  top_model_line="$(echo "${cost_json}" | jq -r '.topModels[0] | select(.) | "\(.model): US$\(.costUsd)"' 2>/dev/null || echo "-")"
  top_job_line="$(echo "${cost_json}" | jq -r '.topJobs[0] | select(.) | "\(.name): US$\(.costUsd)"' 2>/dev/null || echo "-")"

  report "💸 Custo IA hoje: R\$${total_brl} (~US\$${total_usd}) | Tokens=${total_tokens} | câmbio=${GOV_COST_USD_BRL}"
  report "  Top modelo: ${top_model_line}"
  report "  Top cron: ${top_job_line}"

  over_alert="$(python3 - "$total_brl" "${GOV_DAILY_COST_ALERT_BRL}" <<'PY'
import sys
try:
    print("1" if float(sys.argv[1]) >= float(sys.argv[2]) else "0")
except Exception:
    print("0")
PY
)"
  over_critical="$(python3 - "$total_brl" "${GOV_DAILY_COST_CRITICAL_BRL}" <<'PY'
import sys
try:
    print("1" if float(sys.argv[1]) >= float(sys.argv[2]) else "0")
except Exception:
    print("0")
PY
)"

  if [[ "${over_alert}" == "1" ]]; then
    severity="medium"
    [[ "${over_critical}" == "1" ]] && severity="high"
    report "🚨 Custo IA acima do limite: R\$${total_brl} (alerta=${GOV_DAILY_COST_ALERT_BRL}, crítico=${GOV_DAILY_COST_CRITICAL_BRL})"
    register_bottleneck "ai-daily-cost-high" "${severity}" "Custo diário de IA acima do limite" "Estimativa diária de custo: R\$${total_brl} (~US\$${total_usd}), tokens=${total_tokens}. Top modelo: ${top_model_line}. Top cron: ${top_job_line}." "Reduzir contexto/sessão, preferir modelos flash/lite em rotinas, evitar mídia quando texto atende e abrir melhoria estrutural para Engenheiro de Prompt."
    if can_trigger_optimizer_now "${GOV_COST_OPTIMIZER_TRIGGER_GAP_MS}"; then
      force_cron_wake "${OPTIMIZER_CRON}" || true
      report "🛠️ Trigger Otimizador: custo diário alto detectado, execução do cron Otimizador acionada"
    else
      report "ℹ️ Trigger Otimizador: custo diário alto detectado, mas Otimizador já rodou recentemente"
    fi
  else
    report "✅ Custo IA diário: dentro do limite (alerta=${GOV_DAILY_COST_ALERT_BRL})"
  fi

  if [[ "${unpriced_tokens}" =~ ^[0-9]+$ ]] && (( unpriced_tokens > 0 )); then
    report "⚠️ Custo IA: ${unpriced_tokens} tokens sem pricing mapeado (estimativa pode estar subavaliada)"
    register_bottleneck "ai-unpriced-tokens" "medium" "Tokens sem pricing mapeado na auditoria de custo" "${unpriced_tokens} tokens do dia não tiveram modelo com preço mapeado." "Atualizar mapa de preços dos modelos e manter auditoria de custo com cobertura total."
  fi
}

clear_stale_session_locks() {
  local roots=(
    "${OPENCLAW_CONFIG_DIR}/agents/main/sessions"
    "${OPENCLAW_CONFIG_DIR}/agents/einstein/sessions"
    "${OPENCLAW_CONFIG_DIR}/agents/eng-smartenvios/sessions"
    "${OPENCLAW_CONFIG_DIR}/agents/eng-prompt/sessions"
  )
  local now
  now=$(date +%s)
  local cleaned=0

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r lock_file; do
      [[ -f "$lock_file" ]] || continue
      local mtime age_min
      mtime=$(stat -f %m "$lock_file" 2>/dev/null || echo 0)
      age_min=$(( (now - mtime) / 60 ))
      if [[ "$age_min" -ge "$MAX_LOCK_MIN" ]]; then
        rm -f "$lock_file" 2>/dev/null || true
        cleaned=$((cleaned + 1))
        log "Lock obsoleto removido: ${lock_file} (${age_min}min)"
      fi
    done < <(ls "$root"/*.lock 2>/dev/null || true)
  done

  if [[ "$cleaned" -gt 0 ]]; then
    report "🔓 Session locks obsoletos removidos: ${cleaned}"
    register_bottleneck "session-locks-stale" "medium" "Session locks obsoletos recorrentes" "Governança removeu ${cleaned} lock(s) de sessão obsoletos nesta rodada." "Revisar encerramento de sessão dos crons para evitar lock residual recorrente."
  else
    report "✅ Session locks: sem travas obsoletas"
  fi
}

recover_on_model_pressure() {
  local log_file="${OPENCLAW_CONFIG_DIR}/logs/gateway.log"
  [[ -f "$log_file" ]] || return 0

  local pressure
  pressure=$(python3 - "$log_file" <<'PY'
import re
import sys
from pathlib import Path
p = Path(sys.argv[1])
raw = p.read_bytes()[-2_000_000:]
txt = raw.decode("utf-8", errors="ignore")
patterns = [
    r"API rate limit reached",
    r"Provider anthropic is in cooldown",
    r"No available auth profile for openai-codex",
    r"session file locked"
]
hits = sum(len(re.findall(pat, txt)) for pat in patterns)
print(hits)
PY
  )

  if [[ "${pressure:-0}" -ge 3 ]]; then
    log "Pressão de modelo detectada (${pressure} eventos)"
    report "⚠️ Pressão de modelos detectada (${pressure} eventos)"
    register_bottleneck "model-pressure" "medium" "Pressão recorrente de modelos/provedores" "Foram detectados ${pressure} eventos de rate limit/cooldown no gateway." "Revisar distribuição de modelos, espaçamento de crons e fallback para reduzir cooldown/rate limit."
    # Primeiro: tentar recuperar reduzindo o desperdício (reset de sessões overflow).
    prune_overflow_cron_sessions

    # Opcional: restart do gateway só quando explicitamente habilitado (mais disruptivo).
    if [[ "${GOV_GATEWAY_RESTART_ON_PRESSURE}" == "true" ]]; then
      log "Reinício do gateway habilitado — agendado para o fim da rodada"
      GATEWAY_RESTART_REQUESTED="true"
    fi
  else
    report "✅ Pressão de modelos: normal"
  fi
}

recover_on_discord_gateway_outage() {
  local health_script="${DISCORD_GATEWAY_HEALTH_SCRIPT}"
  if [[ ! -x "${health_script}" ]]; then
    report "⚠️ Discord gateway health: checker ausente (${health_script})"
    register_bottleneck "discord-health-script-missing" "high" "Checker de saúde Discord ausente" "Governança não encontrou ${health_script} para validar disponibilidade do bot no Discord." "Restaurar workspace/scripts/discord-gateway-health.sh e manter esse check na rodada."
    return 0
  fi

  local health_json
  health_json="$(
    DISCORD_HEALTH_WINDOW_MIN="${GOV_DISCORD_HEALTH_WINDOW_MIN}" \
    DISCORD_LOGIN_STALE_MIN="${GOV_DISCORD_LOGIN_STALE_MIN}" \
    DISCORD_ERROR_SCORE_THRESHOLD="${GOV_DISCORD_ERROR_SCORE_THRESHOLD}" \
      "${health_script}" 2>/dev/null || true
  )"

  if ! echo "${health_json}" | jq -e . >/dev/null 2>&1; then
    report "⚠️ Discord gateway health: checker retornou saída inválida"
    register_bottleneck "discord-health-check-invalid" "medium" "Saída inválida do checker Discord" "Governança recebeu payload inválido ao executar ${health_script}." "Revisar parser/logs do checker e garantir JSON válido em toda execução."
    return 0
  fi

  local issue reason score dns_errors reconnect_errors preclose_errors login_age
  issue="$(echo "${health_json}" | jq -r '.issue // false' 2>/dev/null || echo false)"
  reason="$(echo "${health_json}" | jq -r '.reason // "unknown"' 2>/dev/null || echo unknown)"
  score="$(echo "${health_json}" | jq -r '.errorScore // 0' 2>/dev/null || echo 0)"
  dns_errors="$(echo "${health_json}" | jq -r '.dnsErrors // 0' 2>/dev/null || echo 0)"
  reconnect_errors="$(echo "${health_json}" | jq -r '.maxReconnectErrors // 0' 2>/dev/null || echo 0)"
  preclose_errors="$(echo "${health_json}" | jq -r '.websocketPrecloseErrors // 0' 2>/dev/null || echo 0)"
  login_age="$(echo "${health_json}" | jq -r '.lastDiscordLoginAgeMin // -1' 2>/dev/null || echo -1)"

  [[ "${score}" =~ ^-?[0-9]+$ ]] || score=0
  [[ "${dns_errors}" =~ ^-?[0-9]+$ ]] || dns_errors=0
  [[ "${reconnect_errors}" =~ ^-?[0-9]+$ ]] || reconnect_errors=0
  [[ "${preclose_errors}" =~ ^-?[0-9]+$ ]] || preclose_errors=0
  [[ "${login_age}" =~ ^-?[0-9]+$ ]] || login_age=-1

  local login_very_stale
  login_very_stale="$(echo "${health_json}" | jq -r '.loginVeryStale // false' 2>/dev/null || echo false)"

  if [[ "${issue}" != "true" ]]; then
    report "✅ Discord gateway: estável (score=${score}, dns=${dns_errors}, reconnect=${reconnect_errors}, ws_preclose=${preclose_errors})"
    return 0
  fi

  local severity="high"
  [[ "${reason}" == "login-stale-no-runtime" ]] && severity="critical"

  report "⚠️ Discord gateway: instável (reason=${reason}, score=${score}, dns=${dns_errors}, reconnect=${reconnect_errors}, ws_preclose=${preclose_errors}, login_age=${login_age}min)"
  register_bottleneck "discord-gateway-instability" "${severity}" "Bot Discord com sinais de indisponibilidade" "Checker detectou reason=${reason}, score=${score}, dns=${dns_errors}, reconnect=${reconnect_errors}, ws_preclose=${preclose_errors}, last_login_age_min=${login_age}." "Aplicar restart automático com cooldown e revisar resolução DNS/rede do host para gateway.discord.gg."

  # Para login-stale-no-runtime, usar cooldown reduzido (5 min) para recuperar mais rápido
  local effective_cooldown="${GOV_DISCORD_RECOVERY_COOLDOWN_SEC}"
  if [[ "${reason}" == "login-stale-no-runtime" ]]; then
    effective_cooldown=$(( GOV_DISCORD_RECOVERY_COOLDOWN_SEC / 3 ))
    [[ "${effective_cooldown}" -lt 300 ]] && effective_cooldown=300
  fi

  local decision
  decision="$(python3 - "${GOV_DISCORD_RECOVERY_STATE_FILE}" "${effective_cooldown}" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
cooldown = int(sys.argv[2])
now = int(time.time())

state = {}
if state_path.exists():
    try:
        raw = json.loads(state_path.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            state = raw
    except Exception:
        state = {}

last = int(state.get("lastDiscordRecoveryTs") or 0)
elapsed = (now - last) if last > 0 else (cooldown + 1)
if elapsed >= cooldown:
    state["lastDiscordRecoveryTs"] = now
    state["consecutiveRecoveries"] = int(state.get("consecutiveRecoveries") or 0) + 1
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"allow|0|{state['consecutiveRecoveries']}")
else:
    print(f"deny|{max(1, cooldown - elapsed)}|{int(state.get('consecutiveRecoveries') or 0)}")
PY
)"

  local action wait_sec consecutive_recoveries
  action="$(echo "${decision}" | cut -d'|' -f1)"
  wait_sec="$(echo "${decision}" | cut -d'|' -f2)"
  consecutive_recoveries="$(echo "${decision}" | cut -d'|' -f3)"
  [[ "${wait_sec}" =~ ^[0-9]+$ ]] || wait_sec=0
  [[ "${consecutive_recoveries}" =~ ^[0-9]+$ ]] || consecutive_recoveries=0

  if [[ "${action}" != "allow" ]]; then
    report "⏸️ Discord autocura em cooldown: aguardar=${wait_sec}s (reason=${reason})"
    register_bottleneck "discord-gateway-instability-cooldown" "medium" "Autocura do Discord em cooldown" "Instabilidade Discord detectada, mas restart automático ainda em cooldown (${wait_sec}s)." "Confirmar se o bot voltou a ficar online no Discord e revisar origem da falha de DNS/rede."
    return 0
  fi

  if ocw_gateway_restart >/dev/null 2>&1; then
    report "✅ Discord autocura: gateway reiniciado com sucesso após instabilidade (tentativa #${consecutive_recoveries})"

    # Verificar se o restart realmente reconectou (aguardar até 30s)
    local verify_ok=false
    for i in 1 2 3; do
      sleep 10
      local post_health
      post_health="$(
        DISCORD_HEALTH_WINDOW_MIN="${GOV_DISCORD_HEALTH_WINDOW_MIN}" \
        DISCORD_LOGIN_STALE_MIN="${GOV_DISCORD_LOGIN_STALE_MIN}" \
        DISCORD_ERROR_SCORE_THRESHOLD="${GOV_DISCORD_ERROR_SCORE_THRESHOLD}" \
          "${health_script}" 2>/dev/null || true
      )"
      local post_issue
      post_issue="$(echo "${post_health}" | jq -r '.issue // true' 2>/dev/null || echo true)"
      if [[ "${post_issue}" != "true" ]]; then
        verify_ok=true
        break
      fi
    done

    if [[ "${verify_ok}" == "true" ]]; then
      report "✅ Discord pós-restart: verificação OK — bot reconectado"
      # Zerar contador de recuperações consecutivas
      python3 -c "
import json; from pathlib import Path
p = Path('${GOV_DISCORD_RECOVERY_STATE_FILE}')
s = json.loads(p.read_text()) if p.exists() else {}
s['consecutiveRecoveries'] = 0
p.write_text(json.dumps(s, indent=2))
" 2>/dev/null || true
    else
      report "⚠️ Discord pós-restart: verificação falhou — bot pode não ter reconectado"
      register_bottleneck "discord-gateway-restart-no-reconnect" "critical" "Gateway reiniciado mas Discord não reconectou" "Restart executado (tentativa #${consecutive_recoveries}) mas checker ainda reporta issue após 30s." "Verificar DNS/rede, credenciais do bot Discord e logs do gateway manualmente."
    fi
  else
    report "❌ Discord autocura: falha ao reiniciar gateway"
    register_bottleneck "discord-gateway-restart-failed" "critical" "Falha na autocura após indisponibilidade Discord" "Governança detectou instabilidade do bot Discord e falhou ao reiniciar o gateway." "Executar recovery manual imediato (restart do serviço + validação de DNS/rede) e abrir card de correção estrutural."
  fi

  # Alerta WhatsApp direto quando Discord fica prolongadamente down (login > 60min ou 3+ restarts consecutivos sem sucesso)
  if [[ "${login_age}" -ge 60 ]] || [[ "${consecutive_recoveries}" -ge 3 ]]; then
    local wa_target
    wa_target="$(resolve_whatsapp_target)"
    if [[ -n "${wa_target:-}" ]]; then
      local alert_msg="ALERTA Discord offline"
      alert_msg="${alert_msg}
- Último login: ${login_age}min atrás"
      alert_msg="${alert_msg}
- Reason: ${reason}"
      alert_msg="${alert_msg}
- Restarts consecutivos: ${consecutive_recoveries}"
      alert_msg="${alert_msg}
- Ação: restart automático executado"
      if [[ "${verify_ok:-false}" == "true" ]]; then
        alert_msg="${alert_msg}
- Status: reconectado com sucesso"
      else
        alert_msg="${alert_msg}
- Status: NÃO reconectou — requer verificação manual"
      fi
      openclaw message send --channel whatsapp --to "${wa_target}" --message "${alert_msg}" >/dev/null 2>&1 || true
      report "📱 Alerta WhatsApp enviado: Discord prolongadamente offline"
    fi
  fi
}

recover_on_gateway_token_mismatch() {
  local log_file="${OPENCLAW_CONFIG_DIR}/logs/gateway.log"
  [[ -f "$log_file" ]] || {
    report "ℹ️ Gateway token mismatch: log indisponível"
    return 0
  }

  local analysis
  analysis="$(python3 - "$log_file" "${GOV_GATEWAY_RECOVERY_WINDOW_MIN}" <<'PY'
import re
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
window_min = int(sys.argv[2])
window_sec = max(60, window_min * 60)
now = int(time.time())
cutoff = now - window_sec

raw = path.read_bytes()[-3_000_000:]
txt = raw.decode("utf-8", errors="ignore")

ts_patterns = [
    re.compile(r'time":"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})'),
    re.compile(r'(\d{2}:\d{2}:\d{2}) \[.*?\]'),
]

token_mismatch = 0
discord_closed = 0
lines = txt.splitlines()
for ln in lines:
    if "token_mismatch" not in ln and "WebSocket connection closed with code 1005" not in ln and "WebSocket connection closed with code 1006" not in ln:
        continue
    ts = None
    m = ts_patterns[0].search(ln)
    if m:
        try:
            ts = int(time.mktime(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")))
        except Exception:
            ts = None
    if ts is None:
        m = ts_patterns[1].search(ln)
        if m:
            try:
                hh, mm, ss = map(int, m.group(1).split(":"))
                lt = time.localtime(now)
                ts = int(time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, hh, mm, ss, lt.tm_wday, lt.tm_yday, lt.tm_isdst)))
                if ts > now + 60:
                    ts -= 86400
            except Exception:
                ts = None
    if ts is not None and ts < cutoff:
        continue
    if "token_mismatch" in ln:
        token_mismatch += 1
    if "WebSocket connection closed with code 1005" in ln or "WebSocket connection closed with code 1006" in ln:
        discord_closed += 1

print(f"{token_mismatch}|{discord_closed}")
PY
)"

  local mismatch_count close_count
  mismatch_count="${analysis%%|*}"
  close_count="${analysis##*|}"
  [[ "${mismatch_count:-}" =~ ^[0-9]+$ ]] || mismatch_count=0
  [[ "${close_count:-}" =~ ^[0-9]+$ ]] || close_count=0

  # Evita restart agressivo por 1005/1006 transitório do Discord.
  # Restart aqui só quando houver sinal forte de token_mismatch real.
  if (( mismatch_count < GOV_GATEWAY_TOKEN_MISMATCH_THRESHOLD )); then
    report "✅ Gateway sessão/Discord: estável (token_mismatch=${mismatch_count}, ws_close=${close_count})"
    return 0
  fi

  local decision
  decision="$(python3 - "${GOV_GATEWAY_RECOVERY_STATE_FILE}" "${GOV_GATEWAY_RECOVERY_COOLDOWN_SEC}" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
cooldown = int(sys.argv[2])
now = int(time.time())

last = 0
if state_path.exists():
    try:
        st = json.loads(state_path.read_text(encoding="utf-8"))
        last = int(st.get("lastGatewayRecoveryTs") or 0)
    except Exception:
        last = 0

elapsed = (now - last) if last > 0 else (cooldown + 1)
if elapsed >= cooldown:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps({"lastGatewayRecoveryTs": now}, ensure_ascii=False, indent=2), encoding="utf-8")
    print("allow|0")
else:
    print(f"deny|{max(1, cooldown - elapsed)}")
PY
)"

  local action wait_sec
  action="${decision%%|*}"
  wait_sec="${decision##*|}"
  [[ "${wait_sec:-}" =~ ^[0-9]+$ ]] || wait_sec=0

  if [[ "${action}" != "allow" ]]; then
    report "⏸️ Gateway autocura em cooldown: token_mismatch=${mismatch_count}, ws_close=${close_count}, aguardar=${wait_sec}s"
    register_bottleneck "gateway-token-mismatch-cooldown" "medium" "Autocura de gateway em cooldown" "Padrão de token_mismatch/ws_close detectado, mas restart automático aguardando cooldown (${wait_sec}s)." "Fechar sessões clientes antigas e validar token único do WebSocket para reduzir reconexões inválidas."
    return 0
  fi

  report "⚠️ Gateway instável por token_mismatch: token_mismatch=${mismatch_count}, ws_close=${close_count} (janela=${GOV_GATEWAY_RECOVERY_WINDOW_MIN}m)"
  register_bottleneck "gateway-token-mismatch" "high" "Instabilidade por token_mismatch" "Detectados ${mismatch_count} token_mismatch (ws_close=${close_count}) na janela recente." "Reiniciar gateway automaticamente com cooldown e orientar fechamento de clientes/sessões antigas com token desatualizado."

  if ocw_gateway_restart >/dev/null 2>&1; then
    report "✅ Gateway recuperado automaticamente após token_mismatch/Discord loop"
  else
    report "❌ Falha no restart automático após token_mismatch/Discord loop"
    register_bottleneck "gateway-token-mismatch-restart-failed" "critical" "Falha na autocura de gateway após token_mismatch" "Governança detectou padrão de token_mismatch/ws_close e falhou ao reiniciar gateway." "Executar recovery manual (restart + limpeza de sessões clientes) e revisar credenciais/token do canal Discord."
  fi
}

recover_einstein_unanswered_mentions() {
  local channels_raw="${GOV_EINSTEIN_CHANNEL_IDS:-}"
  local bot_id="${GOV_EINSTEIN_BOT_ID:-}"
  local history_limit="${GOV_EINSTEIN_HISTORY_LIMIT:-150}"
  local window_min="${GOV_EINSTEIN_RECOVERY_WINDOW_MIN:-1440}"
  local pending_grace_sec="${GOV_EINSTEIN_PENDING_GRACE_SEC:-120}"
  local recovery_timeout_sec="${GOV_EINSTEIN_RECOVERY_TIMEOUT_SEC:-240}"
  local cooldown_sec="${GOV_EINSTEIN_RECOVERY_COOLDOWN_SEC:-900}"
  local backup_agent_id="${GOV_EINSTEIN_BACKUP_AGENT_ID:-einstein-backup}"
  local retry_delay_sec="${GOV_EINSTEIN_RECOVERY_RETRY_DELAY_SEC:-3}"
  local thinking_level="${GOV_EINSTEIN_RECOVERY_THINKING:-minimal}"
  local failure_notify="${GOV_EINSTEIN_FAILURE_NOTIFY:-true}"
  local max_per_round="${GOV_EINSTEIN_RECOVERY_MAX_PER_ROUND:-12}"
  local max_pending_per_channel="${GOV_EINSTEIN_RECOVERY_MAX_PENDING_PER_CHANNEL:-1}"

  if [[ -z "${channels_raw//[[:space:]]/}" ]] || [[ -z "${bot_id//[[:space:]]/}" ]]; then
    report "ℹ️ Einstein autocura: configuração de canais/bot ausente"
    return 0
  fi

  local -a channels
  IFS=',' read -r -a channels <<<"${channels_raw}"

  local pending_found=0
  local recovered=0
  local recovered_with_backup=0
  local failed_mentions=0
  local failure_notices=0
  local skipped_grace=0
  local skipped_cooldown=0
  local attempts=0
  local round_limit_hit=0
  local channel_id

  [[ "${retry_delay_sec}" =~ ^[0-9]+$ ]] || retry_delay_sec=3
  [[ "${max_per_round}" =~ ^[0-9]+$ ]] || max_per_round=12
  (( max_per_round > 0 )) || max_per_round=12
  [[ "${max_pending_per_channel}" =~ ^[0-9]+$ ]] || max_pending_per_channel=1
  (( max_pending_per_channel > 0 )) || max_pending_per_channel=1

  for channel_id in "${channels[@]}"; do
    if (( round_limit_hit == 1 )); then
      break
    fi

    channel_id="$(echo "${channel_id}" | tr -d '[:space:]')"
    [[ -z "${channel_id}" ]] && continue

    local read_json
    read_json="$(openclaw message read --channel discord --target "${channel_id}" --limit "${history_limit}" --json 2>/dev/null || echo '{}')"

    local analysis_json
    analysis_json="$(
      python3 - "${bot_id}" "${window_min}" "${max_pending_per_channel}" <<'PY' <<<"${read_json}" 2>/dev/null || echo '{"pendingMentions":[]}'
import json
import re
import sys
import time

bot_id = str(sys.argv[1]).strip()
window_min = max(1, int(float(sys.argv[2])))
max_pending = max(1, int(float(sys.argv[3])))
window_ms = window_min * 60 * 1000
now_ms = int(time.time() * 1000)

try:
    data = json.loads(sys.stdin.read() or "{}")
except Exception:
    data = {}

payload = data.get("payload") if isinstance(data, dict) else {}
messages = payload.get("messages") if isinstance(payload, dict) else []
if not isinstance(messages, list):
    messages = []

def msg_ts(msg):
    try:
        return int(msg.get("timestampMs") or 0)
    except Exception:
        return 0

def is_from_bot(msg):
    author = msg.get("author") or {}
    author_id = str(author.get("id") or "")
    return (author_id == bot_id) or bool(author.get("bot"))

def content_text(msg):
    value = msg.get("content")
    return value if isinstance(value, str) else ""

def has_bot_mention(msg):
    mentions = msg.get("mentions") or []
    if not isinstance(mentions, list):
        mentions = []
    for mention in mentions:
        if isinstance(mention, dict) and str(mention.get("id") or "") == bot_id:
            return True
    content = content_text(msg)
    if content:
        if f"<@{bot_id}>" in content or f"<@!{bot_id}>" in content:
            return True
    return False

def normalize_text(text):
    text = (text or "").strip()
    text = re.sub(r"<@!?[0-9]+>", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()

request_re = re.compile(
    r"\?|(?:\b(?:pode|poderia|consegue|conseguiria|ajuda|favor|por favor|please|"
    r"crie|criar|abra|abrir|gere|gerar|registre|registrar|verifique|verifica|"
    r"analise|analisa|analisar|cotar|cota|consulta|consulte|responda|responde|"
    r"preciso|precisamos)\b)",
    re.I,
)
low_value_re = re.compile(
    r"^(oi|ol[áa]|bom dia|boa tarde|boa noite|kk+|rs+|haha+|valeu|obrigad[oa])[\s!,.?]*$",
    re.I,
)
handoff_re = re.compile(
    r"\b(vou\s+(verificar|ver|analisar|retornar|retorno|cuidar)|deixa\s+comigo|"
    r"j[aá]\s+(criei|abri|acionei|resolvi)|acionamos|encaminhei|retorno\s+at[eé]|"
    r"nova\s+tentativa)\b",
    re.I,
)
tracking_re = re.compile(r"\b(?:SM|BR|PK|TRK)[A-Z0-9]{8,24}\b", re.I)
uuid_re = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b", re.I)
order_ref_re = re.compile(r"\b(?:pedido|order|freight[_\s-]?order)\s*[:#-]?\s*([A-Z0-9-]{5,36})\b", re.I)

filtered = []
for msg in messages:
    if not isinstance(msg, dict):
        continue
    ts = msg_ts(msg)
    if ts <= 0:
        continue
    if (now_ms - ts) <= window_ms:
        filtered.append(msg)

filtered.sort(key=msg_ts)

latest_bot_ts = 0
for msg in filtered:
    ts = msg_ts(msg)
    if is_from_bot(msg) and ts > latest_bot_ts:
        latest_bot_ts = ts

def author_label(msg):
    author = msg.get("author") or {}
    return str(author.get("global_name") or author.get("username") or "usuario")

def find_recent_entities(idx):
    tracking = ""
    order_ref = ""
    for prev in reversed(filtered[:idx]):
        if is_from_bot(prev):
            continue
        txt = normalize_text(content_text(prev))
        if not txt:
            continue
        if not tracking:
            m = tracking_re.search(txt)
            if m:
                tracking = m.group(0).upper()
        if not order_ref:
            m_uuid = uuid_re.search(txt)
            if m_uuid:
                order_ref = m_uuid.group(0)
            else:
                m_ref = order_ref_re.search(txt)
                if m_ref:
                    order_ref = m_ref.group(1)
        if tracking and order_ref:
            break
    return tracking, order_ref

def build_recent_context(idx, max_msgs=8, max_chars=900):
    start = max(0, idx - max_msgs)
    lines = []
    total = 0
    for prev in filtered[start:idx]:
        if is_from_bot(prev):
            continue
        txt = normalize_text(content_text(prev))
        if not txt:
            continue
        line = f"- {author_label(prev)}: {txt}"
        if total + len(line) + 1 > max_chars:
            if not lines:
                lines.append(line[:max_chars])
            break
        lines.append(line)
        total += len(line) + 1
    return "\n".join(lines)

pending_mentions = []
for idx, msg in enumerate(filtered):
    ts = msg_ts(msg)
    if ts <= int(latest_bot_ts or 0):
        continue
    if is_from_bot(msg):
        continue
    if not has_bot_mention(msg):
        continue

    content = content_text(msg)
    norm = normalize_text(content)
    if not norm:
        continue
    if low_value_re.search(norm):
        continue
    if not request_re.search(norm):
        # Autocura só para pedido explícito; evita atravessar conversa em andamento.
        continue

    stale = False
    nonbot_after = 0
    for nxt in filtered[idx + 1 :]:
        nts = msg_ts(nxt)
        if nts <= ts:
            continue
        if is_from_bot(nxt):
            continue
        if has_bot_mention(nxt):
            # Menção mais nova substitui a anterior.
            stale = True
            break
        nonbot_after += 1
        nxt_norm = normalize_text(content_text(nxt))
        if handoff_re.search(nxt_norm):
            # Outro humano já assumiu o contexto.
            stale = True
            break
        if nonbot_after >= 3:
            # Conversa humana seguiu sem cobrar o Einstein novamente.
            stale = True
            break
    if stale:
        continue

    author = msg.get("author") or {}
    author_id = str(author.get("id") or "")
    inferred_tracking, inferred_order_ref = find_recent_entities(idx)
    recent_context = build_recent_context(idx)
    pending_mentions.append({
        "messageId": str(msg.get("id") or ""),
        "timestampMs": int(ts),
        "pendingAgeSec": int(max(0, (now_ms - ts) // 1000)),
        "content": content if isinstance(content, str) else "",
        "authorId": author_id,
        "authorName": str(author.get("global_name") or author.get("username") or ""),
        "inferredTracking": inferred_tracking,
        "inferredOrderRef": inferred_order_ref,
        "context": recent_context,
    })

if pending_mentions:
    pending_mentions.sort(key=lambda item: int(item.get("timestampMs") or 0))
    pending_mentions = pending_mentions[-max_pending:]

print(json.dumps({
    "pendingMentions": pending_mentions,
    "pendingCount": int(len(pending_mentions)),
    "latestBotTs": int(latest_bot_ts),
    "windowMin": int(window_min),
}, ensure_ascii=False))
PY
    )"

    local pending_count
    pending_count="$(echo "${analysis_json}" | jq -r '.pendingCount // 0' 2>/dev/null || echo 0)"
    [[ "${pending_count}" =~ ^[0-9]+$ ]] || pending_count=0
    (( pending_count > 0 )) || continue

    pending_found=$((pending_found + pending_count))

    local pending_item_b64 pending_item
    while IFS= read -r pending_item_b64; do
      [[ -n "${pending_item_b64}" ]] || continue

      if (( attempts >= max_per_round )); then
        round_limit_hit=1
        break
      fi

      pending_item="$(python3 - "${pending_item_b64}" <<'PY'
import base64
import sys

try:
    print(base64.b64decode(sys.argv[1]).decode("utf-8"))
except Exception:
    print("{}")
PY
)"

      local pending_age_sec pending_message_id pending_content pending_author_id pending_author_name
      local pending_context pending_tracking pending_order_ref recovery_input
      pending_age_sec="$(echo "${pending_item}" | jq -r '.pendingAgeSec // 0' 2>/dev/null || echo 0)"
      pending_message_id="$(echo "${pending_item}" | jq -r '.messageId // ""' 2>/dev/null || echo "")"
      pending_content="$(echo "${pending_item}" | jq -r '.content // ""' 2>/dev/null || echo "")"
      pending_author_id="$(echo "${pending_item}" | jq -r '.authorId // ""' 2>/dev/null || echo "")"
      pending_author_name="$(echo "${pending_item}" | jq -r '.authorName // ""' 2>/dev/null || echo "")"
      pending_context="$(echo "${pending_item}" | jq -r '.context // ""' 2>/dev/null || echo "")"
      pending_tracking="$(echo "${pending_item}" | jq -r '.inferredTracking // ""' 2>/dev/null || echo "")"
      pending_order_ref="$(echo "${pending_item}" | jq -r '.inferredOrderRef // ""' 2>/dev/null || echo "")"
      [[ "${pending_age_sec}" =~ ^[0-9]+$ ]] || pending_age_sec=0

      if (( pending_age_sec < pending_grace_sec )); then
        skipped_grace=$((skipped_grace + 1))
        report "⏳ Einstein autocura: menção recente aguardando janela de graça (${pending_age_sec}s/${pending_grace_sec}s) no canal ${channel_id} (msg=${pending_message_id})"
        continue
      fi

      if [[ -z "${pending_content//[[:space:]]/}" ]]; then
        report "⚠️ Einstein autocura: menção pendente sem conteúdo útil no canal ${channel_id} (msg=${pending_message_id})"
        register_bottleneck "einstein-empty-pending-content" "medium" "Menção pendente do Einstein sem conteúdo utilizável" "Governança detectou menção pendente ao Einstein sem texto para reprocessamento (canal=${channel_id}, msg=${pending_message_id})." "Padronizar solicitação com texto explícito no Discord para permitir autocura determinística."
        continue
      fi

      recovery_input="${pending_content}"
      if [[ -n "${pending_tracking//[[:space:]]/}" || -n "${pending_order_ref//[[:space:]]/}" || -n "${pending_context//[[:space:]]/}" ]]; then
        recovery_input+=$'\n\nContexto recente do canal (evitar pedir novamente dados já informados):'
        if [[ -n "${pending_tracking//[[:space:]]/}" ]]; then
          recovery_input+=$'\n'"- Tracking já informado: ${pending_tracking}"
        fi
        if [[ -n "${pending_order_ref//[[:space:]]/}" ]]; then
          recovery_input+=$'\n'"- Referência de pedido já informada: ${pending_order_ref}"
        fi
        if [[ -n "${pending_context//[[:space:]]/}" ]]; then
          recovery_input+=$'\n'"${pending_context}"
        fi
        recovery_input+=$'\n\n'"Instrução: se o dado já estiver no contexto, não pedir novamente; responda com status objetivo e próximo passo."
      fi
      recovery_input="${recovery_input:0:3200}"

      local decision
      decision="$(
        python3 - "${GOV_EINSTEIN_RECOVERY_STATE_FILE}" "${cooldown_sec}" "${channel_id}" "${pending_message_id}" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
cooldown = int(sys.argv[2])
channel_id = str(sys.argv[3])
message_id = str(sys.argv[4])
now = int(time.time())

state = {}
if state_path.exists():
    try:
        raw = json.loads(state_path.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            state = raw
    except Exception:
        state = {}

channels = state.get("channels")
if not isinstance(channels, dict):
    channels = {}

entry = channels.get(channel_id)
if not isinstance(entry, dict):
    entry = {}

processed = entry.get("processedMessages")
if not isinstance(processed, dict):
    processed = {}

last_ts = int(processed.get(message_id) or 0)
elapsed = (now - last_ts) if last_ts > 0 else (cooldown + 1)

if elapsed < cooldown:
    print(f"deny|{max(1, cooldown - elapsed)}|cooldown")
    raise SystemExit(0)

processed[message_id] = now
ttl = max(cooldown * 6, 86400)
processed = {
    str(mid): int(ts)
    for mid, ts in processed.items()
    if str(mid).strip() and (now - int(ts or 0)) <= ttl
}

entry["processedMessages"] = processed
entry["lastRecoveryTs"] = now
entry["lastMessageId"] = message_id
channels[channel_id] = entry
state["channels"] = channels
state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
print("allow|0|ok")
PY
      )"

      local action wait_sec deny_reason
      action="${decision%%|*}"
      wait_sec="$(echo "${decision}" | awk -F'|' '{print $2}')"
      deny_reason="$(echo "${decision}" | awk -F'|' '{print $3}')"
      [[ "${wait_sec}" =~ ^[0-9]+$ ]] || wait_sec=0

      if [[ "${action}" != "allow" ]]; then
        skipped_cooldown=$((skipped_cooldown + 1))
        report "⏸️ Einstein autocura em cooldown: canal=${channel_id} msg=${pending_message_id} aguardar=${wait_sec}s (${deny_reason:-cooldown})"
        register_bottleneck "einstein-mention-stuck-cooldown" "medium" "Autocura do Einstein em cooldown" "Governança detectou menção pendente (canal=${channel_id}, msg=${pending_message_id}), mas a autocura está em cooldown (${wait_sec}s)." "Evitar duplicidade de resposta e ajustar cooldown se backlog de menções pendentes persistir."
        continue
      fi

      local pending_excerpt
      pending_excerpt="${pending_content//$'\n'/ }"
      pending_excerpt="${pending_excerpt//$'\r'/ }"
      pending_excerpt="${pending_excerpt:0:240}"

      report "⚠️ Einstein sem resposta detectado: canal=${channel_id} msg=${pending_message_id} pendente há ${pending_age_sec}s. Acionando autocura."
      register_bottleneck "einstein-mention-stuck" "high" "Einstein sem resposta em menção do Discord" "Menção ao Einstein ficou pendente por ${pending_age_sec}s (canal=${channel_id}, autor=${pending_author_name:-unknown}, msg=${pending_message_id}). Trecho: ${pending_excerpt}" "Manter autocura automática (gateway + reprocessamento do pedido) para eliminar silêncio operacional do Einstein."

      if ! ocw_gateway_health >/dev/null 2>&1; then
        ocw_gateway_restart >/dev/null 2>&1 || true
      fi
      openclaw channels add --channel discord --use-env >/dev/null 2>&1 || true

      attempts=$((attempts + 1))

      local recovery_json recovery_status recovery_error
      recovery_json="$(openclaw agent --agent einstein --channel discord --message "${recovery_input}" --deliver --reply-channel discord --reply-to "${channel_id}" --thinking "${thinking_level}" --timeout "${recovery_timeout_sec}" --json 2>/dev/null || echo '{}')"
      recovery_status="$(echo "${recovery_json}" | jq -r '.status // "error"' 2>/dev/null || echo "error")"
      recovery_error="$(echo "${recovery_json}" | jq -r '(.error.message // .error // .message // .summary // "") | tostring' 2>/dev/null || echo "")"

      if [[ "${recovery_status}" == "ok" ]]; then
        recovered=$((recovered + 1))
        report "✅ Einstein autocura: menção reprocessada com sucesso (canal=${channel_id}, msg=${pending_message_id}, tentativa=primaria)"
      else
        local recovered_here="false"
        report "⚠️ Einstein autocura: tentativa primária falhou (canal=${channel_id}, msg=${pending_message_id}, erro=${recovery_error:-unknown})"

        if [[ -n "${backup_agent_id//[[:space:]]/}" ]] && [[ "${backup_agent_id}" != "einstein" ]]; then
          if (( retry_delay_sec > 0 )); then
            sleep "${retry_delay_sec}"
          fi

          local backup_json backup_status backup_error
          backup_json="$(openclaw agent --agent "${backup_agent_id}" --channel discord --message "${recovery_input}" --deliver --reply-channel discord --reply-to "${channel_id}" --thinking "${thinking_level}" --timeout "${recovery_timeout_sec}" --json 2>/dev/null || echo '{}')"
          backup_status="$(echo "${backup_json}" | jq -r '.status // "error"' 2>/dev/null || echo "error")"
          backup_error="$(echo "${backup_json}" | jq -r '(.error.message // .error // .message // .summary // "") | tostring' 2>/dev/null || echo "")"

          if [[ "${backup_status}" == "ok" ]]; then
            recovered=$((recovered + 1))
            recovered_with_backup=$((recovered_with_backup + 1))
            recovered_here="true"
            report "✅ Einstein autocura: recuperação via contingência (${backup_agent_id}) concluída (canal=${channel_id}, msg=${pending_message_id})"
          else
            report "❌ Einstein autocura: fallback ${backup_agent_id} também falhou (canal=${channel_id}, msg=${pending_message_id}, erro=${backup_error:-unknown})"
          fi
        fi

        if [[ "${recovered_here}" != "true" ]]; then
          failed_mentions=$((failed_mentions + 1))

          if [[ "${failure_notify}" == "true" ]]; then
            local mention_prefix failure_msg
            mention_prefix=""
            if [[ "${pending_author_id}" =~ ^[0-9]+$ ]]; then
              mention_prefix="<@${pending_author_id}> "
            elif [[ -n "${pending_author_name//[[:space:]]/}" ]]; then
              mention_prefix="@${pending_author_name} "
            fi
            failure_msg="${mention_prefix}instabilidade temporária no Einstein. A contingência automática foi acionada e vou retentar. Se for urgente, repita a solicitação em 1-2 minutos."
            if openclaw message send --channel discord --target "${channel_id}" --message "${failure_msg}" >/dev/null 2>&1; then
              failure_notices=$((failure_notices + 1))
              report "📣 Einstein contingência: aviso automático publicado no canal ${channel_id} (msg=${pending_message_id})"
            else
              report "⚠️ Einstein contingência: falha ao publicar aviso no canal ${channel_id} (msg=${pending_message_id})"
            fi
          fi

          register_bottleneck "einstein-recovery-failed" "critical" "Falha na autocura do Einstein" "Governança detectou menção pendente no canal ${channel_id} (msg=${pending_message_id}) e falhou nas tentativas primária+contingência." "Revisar rota agent->discord/Jira, validar credenciais e manter runbook para recuperação sem intervenção manual."
        fi
      fi
    done < <(echo "${analysis_json}" | jq -r '.pendingMentions[]? | @base64' 2>/dev/null)
  done

  if (( round_limit_hit == 1 )); then
    report "⏭️ Einstein autocura: limite por rodada atingido (max=${max_per_round}, tentativas=${attempts}). Pendências restantes serão tratadas nas próximas rodadas."
  fi

  if (( pending_found == 0 )); then
    report "✅ Einstein autonomia: sem menções pendentes na janela (${window_min}min)"
  elif (( failed_mentions == 0 )); then
    if (( recovered_with_backup > 0 )); then
      report "✅ Einstein autonomia: ${recovered} menção(ões) recuperada(s), incluindo ${recovered_with_backup} via contingência (${backup_agent_id})"
    elif (( recovered > 0 )); then
      report "✅ Einstein autonomia: ${recovered} menção(ões) recuperada(s) automaticamente"
    else
      report "⏳ Einstein autonomia: ${pending_found} menção(ões) detectada(s), aguardando grace/cooldown (grace=${skipped_grace}, cooldown=${skipped_cooldown})"
    fi
  else
    report "⚠️ Einstein autonomia: ${failed_mentions} menção(ões) sem recuperação total nesta rodada (avisos enviados=${failure_notices})"
  fi
}

# 1) Health check do gateway
log "Checando saúde do gateway..."
if ocw_gateway_health >/dev/null 2>&1; then
  log "Gateway OK"
  report "✅ Gateway: saudável"
else
  log "Gateway DOWN — tentando restart..."
  report "⚠️ Gateway: DOWN → reiniciando"
  register_bottleneck "gateway-down" "high" "Gateway indisponível na rodada da governança" "Health check inicial falhou; governança iniciou procedimento de restart." "Revisar estabilidade do serviço gateway (launch agent, logs, resource limits)."
  if ocw_gateway_restart >/dev/null 2>&1; then
    log "Gateway recuperado"
    report "✅ Gateway: recuperado após restart"
  else
    log "Gateway FALHOU no restart"
    report "❌ Gateway: falha no restart — intervenção manual"
    register_bottleneck "gateway-restart-failure" "critical" "Gateway não recuperou após restart automático" "Governança tentou restart e o health check continuou falhando." "Criar runbook de recuperação e monitoria pró-ativa para evitar parada total."
    echo -e "$REPORT"
    exit 1
  fi
fi

# 2) Remove session locks obsoletos
log "Checando session locks obsoletos..."
clear_stale_session_locks

# 2a) Detecta locks órfãos/longos da esteira de e-mail
log "Checando locks da esteira Mail (órfãos/longos)..."
check_mail_processing_locks

# 3) Detecta e recupera pressão de modelos/cooldown
log "Checando pressão de modelos e cooldown..."
recover_on_model_pressure

# 3a) Detecta indisponibilidade real do Discord (DNS/login) e faz autocura com cooldown
log "Checando disponibilidade do bot no Discord..."
recover_on_discord_gateway_outage

# 3b) Detecta token mismatch/loop de Discord e faz autocura com cooldown
log "Checando token mismatch e reconexões Discord..."
recover_on_gateway_token_mismatch

# 3c) Detecta menções sem resposta do Einstein e reprocessa automaticamente
log "Checando autonomia do Einstein (menções pendentes no Discord)..."
recover_einstein_unanswered_mentions

# 4) Detecta crons com erros consecutivos
log "Checando crons com erros consecutivos..."
CRON_JSON="$(ocw_cron_list_json 12 2>/dev/null || echo '{"jobs":[]}')"
if [[ "$(echo "$CRON_JSON" | jq -r '.jobs | length' 2>/dev/null || echo 0)" == "0" ]]; then
  if [[ -f "${OPENCLAW_CONFIG_DIR}/cron/jobs.json" ]]; then
    CRON_JSON=$(cat "${OPENCLAW_CONFIG_DIR}/cron/jobs.json" 2>/dev/null || echo '{"jobs":[]}')
    report "⚠️ Cron list via gateway indisponível; usando fallback local de ${OPENCLAW_CONFIG_DIR}/cron/jobs.json"
    register_bottleneck "cron-list-fallback" "medium" "Gateway cron list indisponível" "Governança precisou usar fallback local de cron/jobs.json para continuar a auditoria." "Investigar disponibilidade do endpoint cron list no gateway e adicionar monitoramento preventivo."
  fi
fi

# 4x) Rebind automático dos IDs críticos para evitar drift entre script e runtime.
rebind_critical_cron_ids_from_runtime

# 4a0) Detecta contenção recorrente de execução nas rotinas de e-mail
log "Checando contenção dos crons de Mail..."
audit_mail_cron_contention

# 4a) Contrato crítico (runtime vs arquivo) para evitar drift silencioso
log "Validando contrato crítico dos crons..."
enforce_critical_cron_contract

# 4a1) Auditoria automática do idioma de heartbeat do Presidente (pt-BR obrigatório)
log "Validando idioma do heartbeat do Presidente..."
enforce_president_heartbeat_language

# 4a2) Auditoria automática do idioma de heartbeat do main (pt-BR obrigatório)
log "Validando idioma do heartbeat do main..."
enforce_main_heartbeat_language

# 4aa) Contrato da esteira Mail (mark-read/archive/fluxo unificado)
log "Validando contrato dos scripts de Mail..."
audit_mail_scripts_contract

# 4ab) Guarda de backlog de e-mail (Pro + Personal) com trigger do Otimizador
log "Checando backlog de e-mail (Mail-Pro + Mail-Person)..."
guard_mail_backlogs

# 4ab1) Sinal explícito do Presidente para forçar a execução da cadeia de e-mail
consume_president_force_request

# 4aba) Qualidade operacional do Notion (backlog real + duplicidade de cards)
log "Checando qualidade operacional do Notion..."
check_notion_operational_quality
quarantine_empty_eng_prompt_cards

# 4aba1) Auditoria transacional MCP (Jira + Grafana) com escalonamento automático
log "Auditando MCP (Jira + Grafana)..."
run_mcp_governance_audit

# 4abb) Drenagem ativa de backlog por agente (Aguardando/Priorizado)
log "Drenando backlog de cards por agente (Notion pessoal/profissional)..."
if [[ -n "${NOTION_SMARTENVIOS_API_KEY:-}" ]]; then
  drain_notion_backlog_by_agent "adec12e735dc41a3bb7c274b287f3a10" "${NOTION_SMARTENVIOS_API_KEY}" "Tech"
fi
if [[ -n "${NOTION_PERSONAL_API_KEY:-}" ]]; then
  drain_notion_backlog_by_agent "${NOTION_PERSONAL_DB_ID}" "${NOTION_PERSONAL_API_KEY}" "Pessoal"
fi

# 4ac) Guarda de custo diário de IA com trigger do Otimizador
log "Checando custo diário de IA..."
guard_daily_ai_costs

ERRORED_CRONS=$(echo "$CRON_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for j in data.get('jobs', []):
    errs = j.get('state', {}).get('consecutiveErrors', 0)
    if errs >= ${MAX_CONSECUTIVE_ERRORS}:
        print(f'{j[\"id\"]}|{j.get(\"name\",\"?\")[:40]}|{errs}')
" 2>/dev/null || true)

if [[ -n "$ERRORED_CRONS" ]]; then
  while IFS='|' read -r cron_id cron_name err_count; do
    log "Cron com ${err_count} erros: ${cron_name} (${cron_id})"
    report "⚠️ Cron ${cron_name}: ${err_count} erros consecutivos"
    register_bottleneck "cron-errors-${cron_id}" "high" "Cron com erros consecutivos: ${cron_name}" "Cron ${cron_name} acumulou ${err_count} erros consecutivos." "Revisar causa raiz (prompt/script/env), reduzir erro recorrente e adicionar testes de resiliência."
    ocw_sessions_reset "agent:main:cron:${cron_id}" >/dev/null 2>&1 || true
    ocw_cron_enable "${cron_id}" >/dev/null 2>&1 || true
    report "🔄 ${cron_name}: sessão resetada + re-habilitado"

    # Se for erro de configuração (não-transiente), desabilitar para reduzir custo/ruído até correção.
    if [[ "${GOV_DISABLE_CRON_ON_CONFIG_ERROR}" == "true" ]]; then
      last_err="$(echo "$CRON_JSON" | python3 - "${cron_id}" <<'PY' 2>/dev/null || true
import json, sys
cid = sys.argv[1]
data = json.load(sys.stdin)
for j in data.get("jobs", []):
    if j.get("id") == cid:
        print((j.get("state", {}) or {}).get("lastError", "") or "")
        break
PY
)"
      if echo "${last_err}" | grep -Eqi "No API key found|API key not set|run out of credits|insufficient balance|billing error"; then
        ocw_cron_disable "${cron_id}" >/dev/null 2>&1 || true
        report "⛔ ${cron_name}: desabilitado automaticamente (erro de credencial/billing)"
        register_bottleneck "cron-disabled-${cron_id}" "high" \
          "Cron desabilitado por erro de configuração" \
          "Cron ${cron_name} foi desabilitado após erros repetidos com indício de credencial/billing. lastError: ${last_err:0:220}" \
          "Corrigir credenciais/model fallback e reabilitar o cron. Evita gasto recorrente por falha previsível."
      fi
    fi
  done <<< "$ERRORED_CRONS"
else
  report "✅ Crons: todos sem erros consecutivos"
fi

# Se uma recuperação solicitou restart (pressão de modelos), executar no final para minimizar interrupções durante cron run/edit.
if [[ "${GATEWAY_RESTART_REQUESTED}" == "true" ]]; then
  log "Aplicando restart do gateway (post-ops)..."
  report "🔁 Gateway: restart aplicado (post-ops, por pressão de modelos)"
  if ! ocw_gateway_restart >/dev/null 2>&1; then
    report "❌ Gateway: falha no restart post-ops"
    register_bottleneck "gateway-restart-postops-failure" "high" "Falha ao reiniciar gateway (post-ops)" "Restart solicitado por pressão de modelos falhou no final da rodada." "Revisar logs do gateway e reduzir overflow de sessão/contexto."
  fi
fi

# 4b) Incluir lastError de cada cron no relatório (para Governança identificar e reportar ao Otimizador)
LAST_ERRORS=$(echo "$CRON_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for j in data.get('jobs', []):
    err = j.get('state', {}).get('lastError', '') or ''
    if err:
        name = (j.get('name') or '?')[:45]
        uid = j.get('id', '')[:8]
        # truncar para caber no relatório
        err_short = (err[:280] + '...') if len(err) > 280 else err
        err_short = err_short.replace('\n', ' ')
        print(f'{uid}|{name}|{err_short}')
" 2>/dev/null || true)
if [[ -n "$LAST_ERRORS" ]]; then
  report ""
  report "📋 Últimos erros por cron (identificar e reportar ao Otimizador):"
  while IFS='|' read -r uid name err_short; do
    report "  • ${name} (${uid}): ${err_short}"
  done <<< "$LAST_ERRORS"
fi

# 4c) Detectar erros que indicam falha de integração Notion/script (Governança deve criar card para Eng. Prompt)
NOTION_SCRIPT_FAILURES=$(echo "$CRON_JSON" | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
patterns = [
    r'API key not set', r'notion', r'update_card', r'script não encontrado',
    r'Could not find', r'consulta.*falhou', r'erro.*notion', r'NOTION_',
    r'no such file.*notion', r'notion-helper'
]
out = []
for j in data.get('jobs', []):
    err = (j.get('state', {}).get('lastError') or '')
    if not err:
        continue
    err_lower = err.lower()
    if any(re.search(p, err_lower, re.I) for p in patterns):
        out.append(j.get('name', '?')[:50])
if out:
    print('|'.join(out))
" 2>/dev/null || true)
if [[ -n "$NOTION_SCRIPT_FAILURES" ]]; then
  report ""
  report "⚠️ Possível falha de integração Notion/script (criar card para Engenheiro de Prompt):"
  report "  Crons afetados: ${NOTION_SCRIPT_FAILURES//|/, }"
  report "  Ação: criar card no Notion PESSOAL com título [Eng. Prompt] Falha Notion/script em <cron>, corpo: lastError + causa provável (env/API key, prompt sem notion-helper) + sugestões."
  register_bottleneck "notion-script-failures" "high" "Falhas de integração Notion/script em crons" "Crons afetados: ${NOTION_SCRIPT_FAILURES//|/, }." "Padronizar uso do notion-helper, validar env/API keys e adicionar teste de fumaça do fluxo Notion."
fi

# 4d) Detecta crons consumindo todo o timeout
log "Checando crons próximos do timeout..."
TIMEOUT_ALERTS=$(python3 - "$CRON_JSON" <<'PY'
import json, sys
THRESHOLD = 0.8
DEFAULT_TIMEOUT = 120
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {"jobs": []}
out = []
for job in data.get('jobs', []):
    state = job.get('state', {}) or {}
    duration_ms = state.get('lastDurationMs') or 0
    if duration_ms <= 0:
        continue
    payload = job.get('payload') or {}
    timeout = payload.get('timeoutSeconds') or DEFAULT_TIMEOUT
    try:
        timeout = float(timeout)
    except (TypeError, ValueError):
        timeout = DEFAULT_TIMEOUT
    ratio = (duration_ms / 1000.0) / timeout if timeout else 0
    last_status = (state.get('lastRunStatus') or state.get('lastStatus') or '').lower()
    if ratio >= THRESHOLD or last_status == 'timeout':
        name = (job.get('name') or '?')[:50]
        out.append(f"{job['id']}|{name}|{int(duration_ms/1000)}s|{int(timeout)}s|{int(ratio*100)}%")
if out:
    print('\n'.join(out))
PY
)

if [[ -n "$TIMEOUT_ALERTS" ]]; then
  report ""
  report "⚠️ Crons consumindo quase todo o timeout (sugerir Eng. Prompt ajustar prompt/timeout e revisar espaçamento):"
  while IFS='|' read -r cron_id cron_name dur timeout pct; do
    report "  • ${cron_name}: duração ${dur} (timeout ${timeout}, uso ${pct})"
    register_bottleneck "cron-timeout-${cron_id}" "medium" "Cron próximo do timeout: ${cron_name}" "Duração ${dur} com timeout ${timeout} (uso ${pct})." "Enxugar prompt/script, revisar timeout e distribuir melhor carga entre crons."
  done <<< "$TIMEOUT_ALERTS"
else
  report "✅ Timeouts: margem segura"
fi

# 4e) Auditoria de adoção dos patterns e oportunidades de padronização
log "Auditando adoção do patterns central..."
audit_pattern_adoption

# 5) Detecta crons running por muito tempo
log "Checando crons travados (running > ${MAX_RUNNING_MIN}min)..."
STUCK_CRONS=$(echo "$CRON_JSON" | python3 -c "
import json, sys, time
data = json.load(sys.stdin)
now_ms = int(time.time() * 1000)
max_ms = ${MAX_RUNNING_MIN} * 60 * 1000
for j in data.get('jobs', []):
    running = j.get('state', {}).get('runningAtMs', 0)
    if running > 0 and (now_ms - running) > max_ms:
        mins = int((now_ms - running) / 60000)
        print(f'{j[\"id\"]}|{j.get(\"name\",\"?\")[:40]}|{mins}')
" 2>/dev/null || true)

if [[ -n "$STUCK_CRONS" ]]; then
  while IFS='|' read -r cron_id cron_name stuck_mins; do
    log "Cron travado há ${stuck_mins}min: ${cron_name}"
    report "⚠️ ${cron_name}: travado há ${stuck_mins}min → resetando sessão"
    register_bottleneck "cron-stuck-${cron_id}" "high" "Cron travado por tempo excessivo: ${cron_name}" "Cron ficou em running por ${stuck_mins}min e exigiu reset de sessão." "Revisar timeout, prompt e efeitos colaterais para impedir travamento recorrente."
    openclaw sessions reset "agent:main:cron:${cron_id}" --yes 2>/dev/null || true
  done <<< "$STUCK_CRONS"
else
  report "✅ Crons: nenhum travado"
fi

# 6) Detecta crons com runningAtMs travado (never-ending runs)
log "Checando crons com running fantasma..."
GHOST_RUNS=$(echo "$CRON_JSON" | python3 -c "
import json, sys, time
data = json.load(sys.stdin)
now_ms = int(time.time() * 1000)
max_ms = 30 * 60 * 1000  # 30min max
for j in data.get('jobs', []):
    running = j.get('state', {}).get('runningAtMs', 0)
    if running > 0 and (now_ms - running) > max_ms:
        mins = int((now_ms - running) / 60000)
        print(f'{j[\"id\"]}|{j.get(\"name\",\"?\")[:40]}|{mins}')
" 2>/dev/null || true)

if [[ -n "$GHOST_RUNS" ]]; then
  JOBS_PATH="${OPENCLAW_CONFIG_DIR}/cron/jobs.json"
  while IFS='|' read -r cron_id cron_name ghost_mins; do
    log "Running fantasma há ${ghost_mins}min: ${cron_name} → limpando"
    report "⚠️ ${cron_name}: running fantasma há ${ghost_mins}min → limpo"
    register_bottleneck "cron-ghost-${cron_id}" "high" "Running fantasma em cron: ${cron_name}" "Campo runningAtMs permaneceu preso por ${ghost_mins}min." "Fortalecer encerramento de execução e limpeza de estado ao final de cada rodada."
  done <<< "$GHOST_RUNS"
  
  python3 -c "
import json, time
p = '${JOBS_PATH}'
with open(p) as f: data = json.load(f)
now = int(time.time() * 1000)
for j in data.get('jobs', []):
    r = j.get('state', {}).get('runningAtMs', 0)
    if r > 0 and (now - r) > 30*60*1000:
        j['state'].pop('runningAtMs', None)
with open(p, 'w') as f: json.dump(data, f, indent=2)
print('Ghost runs limpos')
" 2>/dev/null || true
else
  report "✅ Crons: sem running fantasma"
fi

# 7) Escalonamento automático — evita colisão de crons
log "Verificando escalonamento de crons..."
SCHEDULE_FIX=$(echo "$CRON_JSON" | python3 -c "
import json, sys, time

data = json.load(sys.stdin)
now_ms = int(time.time() * 1000)
min_gap = ${MIN_GAP_MS}

jobs_every = []
for j in data.get('jobs', []):
    if not j.get('enabled', True):
        continue
    sched = j.get('schedule', {})
    if sched.get('kind') != 'every':
        continue
    interval = sched.get('everyMs', 0)
    anchor = sched.get('anchorMs', 0)
    if interval <= 0:
        continue
    cycles = max(1, int((now_ms - anchor) / interval))
    next_run = anchor + (cycles * interval)
    if next_run < now_ms:
        next_run += interval
    jobs_every.append({
        'id': j['id'],
        'name': j.get('name', '?')[:35],
        'interval': interval,
        'anchor': anchor,
        'next': next_run
    })

jobs_every.sort(key=lambda x: x['next'])

collisions = 0
fixes = []
for i in range(1, len(jobs_every)):
    gap = jobs_every[i]['next'] - jobs_every[i-1]['next']
    if 0 <= gap < min_gap:
        new_anchor = jobs_every[i]['anchor'] + min_gap - gap
        fixes.append(f'{jobs_every[i][\"id\"]}|{jobs_every[i][\"name\"]}|{gap//1000}s|{min_gap//1000}s')
        jobs_every[i]['anchor'] = new_anchor
        jobs_every[i]['next'] += (min_gap - gap)
        collisions += 1

if collisions == 0:
    print('OK|0')
else:
    for f in fixes:
        print(f)
" 2>/dev/null || echo "OK|0")

if [[ "$SCHEDULE_FIX" == "OK|0" ]]; then
  log "Escalonamento OK — nenhuma colisão detectada"
  report "✅ Escalonamento: sem colisões"
else
  while IFS='|' read -r cron_id cron_name gap_s target_s; do
    log "Colisão detectada: ${cron_name} (gap=${gap_s}, mínimo=${target_s}) — REPORTANDO (anchorMs gerenciado pela grade fixa em KNOWLEDGE.md)"
    report "⚠️ ${cron_name}: gap ${gap_s} (mín=${target_s}) — grade fixa impede ajuste automático"
    register_bottleneck "cron-collision-${cron_id}" "medium" "Colisão de grade entre crons: ${cron_name}" "Gap observado ${gap_s} abaixo do mínimo ${target_s}." "Revisar anchor/frequências na grade fixa para eliminar sobreposição recorrente."
  done <<< "$SCHEDULE_FIX"
fi

# 8) Ajuste dinâmico de frequência baseado em volume
log "Ajustando frequência dinâmica dos crons..."
JOBS_PATH="${OPENCLAW_CONFIG_DIR}/cron/jobs.json"

python3 -c "
import json, time

jobs_path = '${JOBS_PATH}'
with open(jobs_path) as f:
    store = json.load(f)

now_ms = int(time.time() * 1000)
changed = 0

# Faixas dinâmicas (everyMs em ms)
FREQ_MAP = {
    # Presidente: 30/60/120/180 min
    '8c232f9a': {
        'tiers': [1800000, 3600000, 7200000, 10800000],
        'type': 'creator'
    },
    # Diretores: 35/65/125/185 min
    '12c33196': {'tiers': [2100000, 3900000, 7500000, 11100000], 'type': 'director'},
    '9da1331a': {'tiers': [2100000, 3900000, 7500000, 11100000], 'type': 'director'},
    'dd8959b6': {'tiers': [2100000, 3900000, 7500000, 11100000], 'type': 'director'},
    # Mail: frequência fixa 60min (evita execução duplicada por ajuste dinâmico)
    'ae4a0347': {'tiers': [3600000, 3600000, 3600000, 3600000], 'type': 'specialist'},
    '27f27813': {'tiers': [3600000, 3600000, 3600000, 3600000], 'type': 'specialist'},
}

for job in store.get('jobs', []):
    prefix = job['id'][:8]
    if prefix not in FREQ_MAP:
        continue

    conf = FREQ_MAP[prefix]
    tiers = conf['tiers']
    state = job.get('state', {})
    current_every = job.get('schedule', {}).get('everyMs', 0)
    last_dur = state.get('lastDurationMs', 0)
    last_status = state.get('lastRunStatus') or state.get('lastStatus', '')

    # Heurística: duração curta (<30s) = sem trabalho, duração longa (>60s) = teve trabalho
    if last_status != 'ok':
        # Erro: manter freq atual ou subir 1 tier
        new_every = current_every
    elif last_dur > 60000:
        # Trabalho pesado: freq máxima (tier 0)
        new_every = tiers[0]
    elif last_dur > 30000:
        # Trabalho moderado: tier 1
        new_every = tiers[1] if len(tiers) > 1 else tiers[0]
    elif last_dur > 10000:
        # Trabalho leve: tier 1
        new_every = tiers[1] if len(tiers) > 1 else tiers[0]
    elif last_dur > 0:
        # Rápido (<10s): pouco/nenhum trabalho, subir 1 tier
        idx = 0
        for i, t in enumerate(tiers):
            if current_every <= t:
                idx = i
                break
        new_idx = min(idx + 1, len(tiers) - 1)
        new_every = tiers[new_idx]
    else:
        # Nunca rodou: usar tier 0
        new_every = tiers[0]

    if new_every != current_every:
        job['schedule']['everyMs'] = new_every
        changed += 1
        name = job.get('name', '?')[:35]
        print(f'{name}: {current_every//60000}min -> {new_every//60000}min')

if changed > 0:
    with open(jobs_path, 'w') as f:
        json.dump(store, f, indent=2, ensure_ascii=False)
    print(f'Total: {changed} crons ajustados')
else:
    print('OK: nenhum ajuste necessário')
" 2>/dev/null || true

report "$(python3 -c "print('✅ Frequência dinâmica: verificada')" 2>/dev/null || echo '✅ Frequência dinâmica: verificada')"

# 9) Detecta cards Em andamento travados no Notion
log "Checando cards Em andamento no Notion..."

NOTION_DBS=(
  "${NOTION_SMARTENVIOS_API_KEY:-}|adec12e735dc41a3bb7c274b287f3a10|Tech"
  "${NOTION_PERSONAL_API_KEY:-}|bfcbe7a7a3a745489e605e0762af12a9|Pessoal"
)

NOTION_RECOVERY_CANDIDATES_FILE="${RUNTIME_TMP_DIR}/governance-recovery-candidates-${$}.txt"
: > "${NOTION_RECOVERY_CANDIDATES_FILE}"

for entry in "${NOTION_DBS[@]}"; do
  IFS='|' read -r api_key db_id label <<< "$entry"
  [[ -z "$api_key" ]] && continue

  # Check cards Em andamento travados (>20min sem edição)
  STUCK_CARDS=$(curl -sS --connect-timeout 5 --max-time "${GOV_STAGE_TIMEOUT_GENERAL_SEC}" -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{"filter":{"and":[{"property":"Status","select":{"equals":"Em andamento"}},{"property":"Tipo","select":{"equals":"OpenClaw"}}]}}' 2>/dev/null | python3 -c "
import json, sys, datetime
data = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
rows = []
for page in data.get('results', []):
    edited = page.get('last_edited_time', '')
    if edited:
        dt = datetime.datetime.fromisoformat(edited.replace('Z', '+00:00'))
        diff_min = (now - dt).total_seconds() / 60
    else:
        diff_min = 999
    title = ''
    for prop in page.get('properties', {}).values():
        if prop.get('type') == 'title':
            for t in prop.get('title', []):
                title += t.get('plain_text', '')
    agent = ''
    agent_prop = page.get('properties', {}).get('Agente', {})
    if agent_prop.get('type') == 'select' and agent_prop.get('select'):
        agent = agent_prop['select'].get('name', '')
    if diff_min > 20:
        rows.append((int(diff_min), page.get('id', ''), title[:50], agent))
rows.sort(key=lambda x: x[0], reverse=True)
limit = int(${GOV_NOTION_RECOVERY_LIMIT})
for mins, page_id, title, agent in rows[:limit]:
    print(f'{page_id}|{title}|{agent}|{mins}')
" 2>/dev/null || true)

  if [[ -n "$STUCK_CARDS" ]]; then
    while IFS='|' read -r page_id title agent mins; do
      [[ -z "${page_id}" ]] && continue
      echo "${mins}|${label}|stuck|${page_id}|${title}|${agent}" >> "${NOTION_RECOVERY_CANDIDATES_FILE}"
      break
    done <<< "$STUCK_CARDS"
  else
    log "[${label}] Nenhum card Em andamento travado"
  fi

  # Check cards Priorizado abandonados (>MAX_PRIORIZED_MIN sem ninguém pegar)
  ABANDONED_CARDS=$(curl -sS --connect-timeout 5 --max-time "${GOV_STAGE_TIMEOUT_GENERAL_SEC}" -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{"filter":{"and":[{"property":"Status","select":{"equals":"Priorizado"}},{"property":"Tipo","select":{"equals":"OpenClaw"}}]}}' 2>/dev/null | python3 -c "
import json, sys, datetime
data = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
rows = []
for page in data.get('results', []):
    edited = page.get('last_edited_time', '')
    if edited:
        dt = datetime.datetime.fromisoformat(edited.replace('Z', '+00:00'))
        diff_min = (now - dt).total_seconds() / 60
    else:
        diff_min = 999
    title = ''
    for prop in page.get('properties', {}).values():
        if prop.get('type') == 'title':
            for t in prop.get('title', []):
                title += t.get('plain_text', '')
    agent = ''
    agent_prop = page.get('properties', {}).get('Agente', {})
    if agent_prop.get('type') == 'select' and agent_prop.get('select'):
        agent = agent_prop['select'].get('name', '')
    if diff_min > ${MAX_PRIORIZED_MIN}:
        rows.append((int(diff_min), page.get('id', ''), title[:50], agent))
rows.sort(key=lambda x: x[0], reverse=True)
limit = int(${GOV_NOTION_RECOVERY_LIMIT})
for mins, page_id, title, agent in rows[:limit]:
    print(f'{page_id}|{title}|{agent}|{mins}')
" 2>/dev/null || true)

  if [[ -n "$ABANDONED_CARDS" ]]; then
    while IFS='|' read -r page_id title agent mins; do
      [[ -z "${page_id}" ]] && continue
      echo "${mins}|${label}|priorizado|${page_id}|${title}|${agent}" >> "${NOTION_RECOVERY_CANDIDATES_FILE}"
      break
    done <<< "$ABANDONED_CARDS"
  else
    log "[${label}] Nenhum card Priorizado abandonado"
  fi

  # Guarda de roteamento legado + auditoria de comentário de triagem do diretor
  if [[ "$label" == "Tech" ]]; then
    check_legacy_tech_cards "$api_key" "$db_id"
    audit_recent_triage_comments "$api_key" "$db_id" "$label" "Diretor Tech"
  elif [[ "$label" == "Pessoal" ]]; then
    audit_recent_triage_comments "$api_key" "$db_id" "$label" "Diretor Pessoal"
  fi
  audit_mail_card_consistency "$api_key" "$db_id" "$label"
  if [[ "$label" == "Tech" ]]; then
    audit_recent_concluded_without_evidence "$api_key" "$db_id" "$label" "NOTION_SMARTENVIOS_API_KEY"
  elif [[ "$label" == "Pessoal" ]]; then
    audit_recent_concluded_without_evidence "$api_key" "$db_id" "$label" "NOTION_PERSONAL_API_KEY"
  fi
  done

# Recuperação específica do Engenheiro de Prompt (evita card preso em Em andamento por longo período).
recover_stuck_eng_prompt_card
# Recuperação específica do Engenheiro SmartEnvios (evita card preso em Em andamento por longo período).
recover_stuck_eng_smartenvios_card
# Recuperação de cards em status Pausado (reativa para Priorizado com wake do agente).
recover_paused_cards

if [[ -s "${NOTION_RECOVERY_CANDIDATES_FILE}" ]]; then
  # Use sed instead of head to avoid SIGPIPE(141) under `set -o pipefail`.
  chosen="$(sort -t'|' -k1,1nr "${NOTION_RECOVERY_CANDIDATES_FILE}" | sed -n '1p')"
  IFS='|' read -r chosen_mins chosen_label chosen_kind chosen_page_id chosen_title chosen_agent <<< "${chosen}"
  if [[ -n "${chosen_page_id:-}" ]]; then
    if [[ "${chosen_kind}" == "stuck" ]]; then
      log "[${chosen_label}] Card travado há ${chosen_mins}min: '${chosen_title}' (Agente=${chosen_agent})"
      report "⚠️ [${chosen_label}] Card '${chosen_title}' Em andamento há ${chosen_mins}min (Agente=${chosen_agent})"
      register_bottleneck "notion-stuck-${chosen_label}-${chosen_page_id}" "high" "Card travado em Em andamento (${chosen_label})" "Card '${chosen_title}' (Agente=${chosen_agent}) permaneceu ${chosen_mins}min em Em andamento." "Padronizar timeout de execução + heartbeat de progresso e fallback automático para não deixar card preso."
      if ! wake_for_agent "${chosen_agent}" "recuperação"; then
        if [[ "${chosen_mins}" -gt 30 ]]; then
          report "🚨 Alerta: card '${chosen_title}' (Agente=${chosen_agent}) Em andamento há ${chosen_mins}min — intervenção manual"
        fi
      fi
    else
      log "[${chosen_label}] Card Priorizado abandonado há ${chosen_mins}min: '${chosen_title}' (Agente=${chosen_agent})"
      report "🚨 [${chosen_label}] Card '${chosen_title}' Priorizado há ${chosen_mins}min sem execução (Agente=${chosen_agent})"
      register_bottleneck "notion-priorizado-abandonado-${chosen_label}-${chosen_page_id}" "high" "Card Priorizado sem execução (${chosen_label})" "Card '${chosen_title}' (Agente=${chosen_agent}) ficou ${chosen_mins}min em Priorizado sem ser iniciado." "Ajustar roteamento/cron do agente alvo e reforçar wake automático quando houver atraso."
      if ! wake_for_agent "${chosen_agent}" "card abandonado"; then
        report "⚠️ Card '${chosen_title}' (Agente=${chosen_agent}) Priorizado há ${chosen_mins}min — nenhum cron mapeado para forçar"
        register_bottleneck "notion-priorizado-sem-mapeamento-${chosen_label}-${chosen_agent}" "medium" "Agente sem mapeamento de wake (${chosen_label})" "Card Priorizado para Agente=${chosen_agent} sem cron mapeado para recuperação automática." "Atualizar mapa de wake da Governança para esse agente ou ajustar roteamento dos cards."
      fi
    fi
  fi
else
  report "✅ Recuperação Notion: nenhum card elegível para intervenção nesta rodada"
fi

# 6) Contagem final
TOTAL_CRONS=$(echo "$CRON_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
jobs = data.get('jobs', [])
enabled = sum(1 for j in jobs if j.get('enabled'))
print(f'{enabled}/{len(jobs)}')
" 2>/dev/null || echo "?/?")
report "📊 Crons habilitados: ${TOTAL_CRONS}"

# 9) Diagnóstico de pipeline parado / starvation (cron nunca executa por posição na fila)
log "Checando starvation de crons..."
STARVATION=$(echo "$CRON_JSON" | python3 -c "
import json, sys, time
data = json.load(sys.stdin)
now_ms = int(time.time() * 1000)
for j in data.get('jobs', []):
    if not j.get('enabled', True):
        continue
    s = j.get('state', {})
    last = s.get('lastRunAtMs', 0)
    nxt = s.get('nextRunAtMs', 0)
    if nxt > 0 and nxt < now_ms:
        overdue_min = (now_ms - nxt) // 60000
        if last > 0:
            since_last = (now_ms - last) // 60000
            if overdue_min >= 10 and since_last >= 30:
                print(f\"{j['id']}|{j.get('name','?')[:35]}|{overdue_min}min atrasado|{since_last}min sem rodar\")
" 2>/dev/null || true)

if [[ -n "$STARVATION" ]]; then
  while IFS='|' read -r cid cname overdue since; do
    log "Starvation: ${cname} — ${overdue}, ${since}"
    report "🚨 STARVATION: ${cname} — ${overdue}, ${since} (forçar cron ou revisar ordem/anchor)"
    register_bottleneck "cron-starvation-${cid}" "high" "Starvation de cron: ${cname}" "Cron ficou ${overdue}, ${since}." "Revisar grade de execução (anchor/every) e concorrência para impedir filas permanentes."
  done <<< "$STARVATION"
else
  report "✅ Pipeline: sem starvation detectada"
fi

# 9.5) Custo diário
# A estimativa/alerta de custo diário roda via `guard_daily_ai_costs`.
# (Removida a estimativa antiga baseada em CRON_RUNS_DIR/GOV_DAILY_COST_LIMIT_USD, que podia quebrar com `set -u`.)

# 10) Escalonamento autônomo de gargalos para card de melhoria
log "Escalonando gargalos recorrentes para Notion Pessoal..."
auto_escalate_bottlenecks_to_notion

# 10.5) Saúde operacional por resultado real (para painel e relatório não passarem "estável" quando há falhas)
log "Calculando saúde operacional (resultados reais dos papéis)..."
compute_operational_health

# 11) Painel operacional por WhatsApp (cada execução da governança)
log "Enviando painel operacional via WhatsApp..."
send_governance_whatsapp_table

# 12) Telemetria de recuperação (wake/circuit breaker)
report "🧯 Recovery: wakes usados=${WAKES_USED}/${GOV_WAKE_BUDGET_PER_ROUND}, bloqueados=${WAKES_DROPPED}, cooldown=${GOV_WAKE_MIN_GAP_SEC}s"

# 13) Handoff para Otimizador: escrever gargalos desta rodada para o Otimizador ler e evoluir o fluxo
GOV_BOTTLENECKS_FOR_OPTIMIZER="${PROJECT_ROOT}/workspace/docs/operacao/governance-bottlenecks-for-optimizer.md"
if [[ -s "${BOTTLENECK_EVENTS_FILE}" ]]; then
  mkdir -p "$(dirname "${GOV_BOTTLENECKS_FOR_OPTIMIZER}")" 2>/dev/null || true
  {
    echo ""
    echo "## $(date -u '+%Y-%m-%d %H:%M UTC')"
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      key="$(echo "${line}" | jq -r '.key // ""')"
      sev="$(echo "${line}" | jq -r '.severity // ""')"
      title="$(echo "${line}" | jq -r '.title // ""')"
      rec="$(echo "${line}" | jq -r '.recommendation // ""')"
      [[ -n "${key}" ]] && echo "- **${key}** [${sev}]: ${title}"
      [[ -n "${rec}" ]] && echo "  - Recomendação: ${rec}"
    done < "${BOTTLENECK_EVENTS_FILE}"
  } >> "${GOV_BOTTLENECKS_FOR_OPTIMIZER}" 2>/dev/null || true
fi

# Output — cabeçalho com saúde operacional primeiro (nunca passar mensagem de "estável" quando há falhas)
echo ""
echo "=========================================="
echo " RELATÓRIO DE GOVERNANÇA"
echo " $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "=========================================="
if [[ "${OPERATIONAL_HEALTH_STATUS}" == "OK" ]]; then
  echo " SAÚDE OPERACIONAL: OK — fluxo e papéis cumpridos"
else
  echo " SAÚDE OPERACIONAL: ${OPERATIONAL_HEALTH_STATUS} — NÃO reportar como estável"
  if [[ -n "${OPERATIONAL_HEALTH_ISSUES}" ]]; then
    echo -e "${OPERATIONAL_HEALTH_ISSUES}"
  fi
fi
echo "------------------------------------------"
echo -e "$REPORT"
echo "=========================================="
