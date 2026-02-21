#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# governance-check.sh — Health check + recovery + escalonamento automático
###############################################################################

LOG_PREFIX="[governance]"
MAX_CONSECUTIVE_ERRORS=2
MAX_RUNNING_MIN=20
MIN_GAP_MS=180000  # 3min mínimo entre crons (evita rate limit, execução sequencial)
MAX_LOCK_MIN=5
REPORT=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}"
NOTION_HELPER_SCRIPT="${PROJECT_ROOT}/workspace/scripts/notion-helper.sh"
GMAIL_SCRIPT="${PROJECT_ROOT}/workspace/scripts/gmail/gmail.sh"

OPTIMIZER_CRON="3df67742-33a2-48d2-8778-b8da16d0315f"
MAIL_PRO_CRON="ae4a0347-2e03-46ad-8595-6b9476c45d79"
MAIL_PERSON_CRON="27f27813-12d5-4c2d-a66b-7a50d75b2e98"
ENG_PROMPT_CRON="6bdd82c7-081d-486b-9700-0572b9fce72e"
ENG_SMARTENVIOS_CRON="a7b8c9d0-e1f2-3456-7890-abcdef123401"
PRESIDENT_CRON="8c232f9a-b4aa-485f-83c8-99d348bb3176"
DIRECTOR_TECH_CRON="9da1331a-2c84-4191-9e7d-87552039d8f1"
DIRECTOR_PERSONAL_CRON="dd8959b6-0346-487f-8281-591249c8dc31"

log() { echo "${LOG_PREFIX} $(date -u +%H:%M:%S) $*"; }
report() { REPORT="${REPORT}\n$*"; }

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
    "workspace/agents/backend-engineer/AGENTS.md",
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

  if printf '%s\n' "$drift" | grep -q '^ERROR|'; then
    report "🚨 Contrato crítico de crons: falha ao comparar runtime vs cron/jobs.json"
    return
  fi

  # Simplificando - removendo lógica de arrays associativos para compatibilidade
  # Em vez de trackear sync por cron, apenas reportamos todos os drifts
  local changed=0

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
  if printf '%s\n' "$missing" | grep -q '^ERROR|'; then
    report "⚠️ [${label}] Não foi possível auditar comentários de triagem no Notion"
    return
  fi

  report ""
  report "⚠️ [${label}] Cards Priorizado recentes sem assinatura de triagem [${director}]:"
  while IFS='|' read -r page_id title mins; do
    [[ -z "${page_id:-}" ]] && continue
    report "  • ${title} (${mins}min, id=${page_id})"
  done <<< "$missing"
}

check_legacy_tech_cards() {
  local api_key="$1"
  local db_id="$2"
  [[ -z "${api_key:-}" || -z "${db_id:-}" ]] && return

  local legacy
  legacy=$(curl -sS -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
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
  # Fire-and-forget para não bloquear governança quando o gateway oscila.
  (
    openclaw cron run "$cron_id" --timeout 30000 >/dev/null 2>&1 \
      || openclaw cron edit "$cron_id" --wake now --timeout 30000 >/dev/null 2>&1
  ) &
  return 0
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

guard_mail_backlogs() {
  local unread_pro unread_personal
  local active_pro active_personal
  local threshold=80
  local overload=0

  if [[ ! -x "${GMAIL_SCRIPT}" || ! -x "${NOTION_HELPER_SCRIPT}" ]]; then
    report "⚠️ Backlog e-mail: scripts Gmail/Notion indisponíveis para auditoria"
    return
  fi

  unread_pro="$("${GMAIL_SCRIPT}" pro list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
  unread_personal="$("${GMAIL_SCRIPT}" personal list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
  [[ ! "${unread_pro}" =~ ^[0-9]+$ ]] && unread_pro=0
  [[ ! "${unread_personal}" =~ ^[0-9]+$ ]] && unread_personal=0

  report "📬 Backlog e-mail: Pro=${unread_pro} | Personal=${unread_personal} (não lidos)"

  if (( unread_pro >= threshold )); then
    overload=1
    active_pro="$("${NOTION_HELPER_SCRIPT}" query adec12e735dc41a3bb7c274b287f3a10 NOTION_SMARTENVIOS_API_KEY "Mail-Pro" Priorizado "Em andamento" 2>/dev/null | jq -r '.results | length' 2>/dev/null || echo 0)"
    [[ ! "${active_pro}" =~ ^[0-9]+$ ]] && active_pro=0
    report "🚨 Mail-Pro backlog alto: ${unread_pro} não lidos"
    if (( active_pro == 0 )); then
      report "  Ação: sem card ativo Mail-Pro, forçando cadeia Presidente -> Diretor Tech -> Mail-Pro"
      force_cron_wake "${PRESIDENT_CRON}" || true
      sleep 1
      force_cron_wake "${DIRECTOR_TECH_CRON}" || true
      sleep 1
      force_cron_wake "${MAIL_PRO_CRON}" || true
    else
      report "  Ação: ${active_pro} card(s) ativo(s) Mail-Pro; forçando execução imediata do Mail-Pro"
      force_cron_wake "${MAIL_PRO_CRON}" || true
    fi
  fi

  if (( unread_personal >= threshold )); then
    overload=1
    active_personal="$("${NOTION_HELPER_SCRIPT}" query bfcbe7a7a3a745489e605e0762af12a9 NOTION_PERSONAL_API_KEY "Mail-Person" Priorizado "Em andamento" 2>/dev/null | jq -r '.results | length' 2>/dev/null || echo 0)"
    [[ ! "${active_personal}" =~ ^[0-9]+$ ]] && active_personal=0
    report "🚨 Mail-Person backlog alto: ${unread_personal} não lidos"
    if (( active_personal == 0 )); then
      report "  Ação: sem card ativo Mail-Person, forçando cadeia Presidente -> Diretor Pessoal -> Mail-Person"
      force_cron_wake "${PRESIDENT_CRON}" || true
      sleep 1
      force_cron_wake "${DIRECTOR_PERSONAL_CRON}" || true
      sleep 1
      force_cron_wake "${MAIL_PERSON_CRON}" || true
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
    log "Pressão de modelo detectada (${pressure} eventos) — reinício preventivo do gateway"
    report "⚠️ Pressão de modelos detectada (${pressure} eventos) — reinício preventivo"
    openclaw gateway stop 2>/dev/null || true
    sleep 3
    openclaw gateway install --force 2>/dev/null || openclaw gateway install 2>/dev/null || true
    sleep 5
    if openclaw health >/dev/null 2>&1; then
      report "✅ Gateway: recuperado após pressão de modelos"
    else
      report "❌ Gateway: não recuperou após pressão de modelos"
    fi
  else
    report "✅ Pressão de modelos: normal"
  fi
}

# 1) Health check do gateway
log "Checando saúde do gateway..."
if openclaw health >/dev/null 2>&1; then
  log "Gateway OK"
  report "✅ Gateway: saudável"
else
  log "Gateway DOWN — tentando restart..."
  report "⚠️ Gateway: DOWN → reiniciando"
  openclaw gateway stop 2>/dev/null || true
  sleep 3
  openclaw gateway install --force 2>/dev/null || openclaw gateway install 2>/dev/null || true
  sleep 5
  if openclaw health >/dev/null 2>&1; then
    log "Gateway recuperado"
    report "✅ Gateway: recuperado após restart"
  else
    log "Gateway FALHOU no restart"
    report "❌ Gateway: falha no restart — intervenção manual"
    echo -e "$REPORT"
    exit 1
  fi
fi

# 2) Remove session locks obsoletos
log "Checando session locks obsoletos..."
clear_stale_session_locks

# 3) Detecta e recupera pressão de modelos/cooldown
log "Checando pressão de modelos e cooldown..."
recover_on_model_pressure

# 4) Detecta crons com erros consecutivos
log "Checando crons com erros consecutivos..."
CRON_JSON=$(openclaw cron list --json 2>/dev/null || echo '{"jobs":[]}')
if [[ "$(echo "$CRON_JSON" | jq -r '.jobs | length' 2>/dev/null || echo 0)" == "0" ]]; then
  if [[ -f "${OPENCLAW_CONFIG_DIR}/cron/jobs.json" ]]; then
    CRON_JSON=$(cat "${OPENCLAW_CONFIG_DIR}/cron/jobs.json" 2>/dev/null || echo '{"jobs":[]}')
    report "⚠️ Cron list via gateway indisponível; usando fallback local de ${OPENCLAW_CONFIG_DIR}/cron/jobs.json"
  fi
fi

# 4a) Contrato crítico (runtime vs arquivo) para evitar drift silencioso
log "Validando contrato crítico dos crons..."
enforce_critical_cron_contract

# 4aa) Contrato da esteira Mail (mark-read/archive/fluxo unificado)
log "Validando contrato dos scripts de Mail..."
audit_mail_scripts_contract

# 4ab) Guarda de backlog de e-mail (Pro + Personal) com trigger do Otimizador
log "Checando backlog de e-mail (Mail-Pro + Mail-Person)..."
guard_mail_backlogs

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
    openclaw sessions reset "agent:main:cron:${cron_id}" --yes 2>/dev/null || true
    openclaw cron edit "${cron_id}" --enable 2>/dev/null || true
    report "🔄 ${cron_name}: sessão resetada + re-habilitado"
  done <<< "$ERRORED_CRONS"
else
  report "✅ Crons: todos sem erros consecutivos"
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
    last_status = (state.get('lastStatus') or '').lower()
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
    last_status = state.get('lastStatus', '')

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

for entry in "${NOTION_DBS[@]}"; do
  IFS='|' read -r api_key db_id label <<< "$entry"
  [[ -z "$api_key" ]] && continue

  # Check cards Em andamento travados (>20min sem edição)
  STUCK_CARDS=$(curl -sS -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{"filter":{"and":[{"property":"Status","select":{"equals":"Em andamento"}},{"property":"Tipo","select":{"equals":"OpenClaw"}}]}}' 2>/dev/null | python3 -c "
import json, sys, datetime
data = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
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
        print(f'{page[\"id\"]}|{title[:50]}|{agent}|{int(diff_min)}')
" 2>/dev/null || true)

  if [[ -n "$STUCK_CARDS" ]]; then
    while IFS='|' read -r _page_id title agent mins; do
      log "[${label}] Card travado há ${mins}min: '${title}' (Agente=${agent})"
      report "⚠️ [${label}] Card '${title}' Em andamento há ${mins}min (Agente=${agent})"

      case "$agent" in
        Mail-Pro)
          log "Acordando cron Mail-Pro via wake..."
          force_cron_wake "${MAIL_PRO_CRON}"
          report "🔄 Wake enviado para cron Mail-Pro (recuperação)"
          ;;
        Mail-Person)
          log "Acordando cron Mail-Person via wake..."
          force_cron_wake "${MAIL_PERSON_CRON}"
          report "🔄 Wake enviado para cron Mail-Person (recuperação)"
          ;;
        "Engenheiro de Prompt")
          log "Acordando cron Engenheiro de Prompt via wake..."
          force_cron_wake "${ENG_PROMPT_CRON}"
          report "🔄 Wake enviado para cron Engenheiro de Prompt (recuperação)"
          ;;
        "Engenheiro SmartEnvios")
          log "Acordando cron Engenheiro SmartEnvios via wake..."
          force_cron_wake "${ENG_SMARTENVIOS_CRON}"
          report "🔄 Wake enviado para cron Engenheiro SmartEnvios (recuperação)"
          ;;
        *)
          if [[ "$mins" -gt 30 ]]; then
            report "🚨 Alerta: card '${title}' (Agente=${agent}) Em andamento há ${mins}min — intervenção manual"
          fi
          ;;
      esac
    done <<< "$STUCK_CARDS"
  else
    log "[${label}] Nenhum card Em andamento travado"
  fi

  # Check cards Priorizado abandonados (>60min sem ninguém pegar)
  ABANDONED_CARDS=$(curl -sS -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{"filter":{"and":[{"property":"Status","select":{"equals":"Priorizado"}},{"property":"Tipo","select":{"equals":"OpenClaw"}}]}}' 2>/dev/null | python3 -c "
import json, sys, datetime
data = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
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
    if diff_min > 60:
        print(f'{page[\"id\"]}|{title[:50]}|{agent}|{int(diff_min)}')
" 2>/dev/null || true)

  if [[ -n "$ABANDONED_CARDS" ]]; then
    while IFS='|' read -r _page_id title agent mins; do
      log "[${label}] Card Priorizado abandonado há ${mins}min: '${title}' (Agente=${agent})"
      report "🚨 [${label}] Card '${title}' Priorizado há ${mins}min sem execução (Agente=${agent})"

      case "$agent" in
        Mail-Pro)
          force_cron_wake "${MAIL_PRO_CRON}"
          report "🔄 Wake enviado para cron Mail-Pro (card abandonado)"
          ;;
        Mail-Person)
          force_cron_wake "${MAIL_PERSON_CRON}"
          report "🔄 Wake enviado para cron Mail-Person (card abandonado)"
          ;;
        "Engenheiro de Prompt")
          force_cron_wake "${ENG_PROMPT_CRON}"
          report "🔄 Wake enviado para cron Engenheiro de Prompt (card abandonado)"
          ;;
        *)
          report "⚠️ Card '${title}' (Agente=${agent}) Priorizado há ${mins}min — nenhum cron mapeado para forçar"
          ;;
      esac
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
  done

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
  while IFS='|' read -r _cid cname overdue since; do
    log "Starvation: ${cname} — ${overdue}, ${since}"
    report "🚨 STARVATION: ${cname} — ${overdue}, ${since} (forçar cron ou revisar ordem/anchor)"
  done <<< "$STARVATION"
else
  report "✅ Pipeline: sem starvation detectada"
fi

# Output
echo ""
echo "=========================================="
echo " RELATÓRIO DE GOVERNANÇA"
echo " $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "=========================================="
echo -e "$REPORT"
echo "=========================================="
