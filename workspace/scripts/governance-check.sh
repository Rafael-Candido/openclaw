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

log() { echo "${LOG_PREFIX} $(date -u +%H:%M:%S) $*"; }
report() { REPORT="${REPORT}\n$*"; }

force_cron_wake() {
  local cron_id="$1"
  openclaw cron wake "$cron_id" --mode now >/dev/null 2>&1 || true
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
    # Mail: 15/30/60/120 min
    'ae4a0347': {'tiers': [900000, 1800000, 3600000, 7200000], 'type': 'specialist'},
    '27f27813': {'tiers': [900000, 1800000, 3600000, 7200000], 'type': 'specialist'},
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

MAIL_PRO_CRON="ae4a0347-2e03-46ad-8595-6b9476c45d79"
MAIL_PERSON_CRON="27f27813-12d5-4c2d-a66b-7a50d75b2e98"
ENG_PROMPT_CRON="6bdd82c7-081d-486b-9700-0572b9fce72e"
ENG_SMARTENVIOS_CRON="a7b8c9d0-e1f2-3456-7890-abcdef123401"

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
