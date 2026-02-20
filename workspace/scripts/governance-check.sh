#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# governance-check.sh — Health check + recovery para agentes OpenClaw
###############################################################################

LOG_PREFIX="[governance]"
MAX_CONSECUTIVE_ERRORS=2
MAX_RUNNING_MIN=20
REPORT=""

log() { echo "${LOG_PREFIX} $(date -u +%H:%M:%S) $*"; }
report() { REPORT="${REPORT}\n$*"; }

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

# 2) Detecta crons com erros consecutivos
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

# 3) Detecta crons running por muito tempo
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

# 4) Detecta especialistas com cards em Em andamento que precisam ser forçados
log "Checando cards Em andamento no Notion (workspace Tech)..."
if [[ -f /private/var/www/openclaw/.env ]]; then
  source /private/var/www/openclaw/.env 2>/dev/null || true
fi

NOTION_DBS=(
  "${NOTION_SMARTENVIOS_API_KEY:-}|adec12e735dc41a3bb7c274b287f3a10|Tech"
  "${NOTION_PERSONAL_API_KEY:-}|bfcbe7a7a3a745489e605e0762af12a9|Pessoal"
)

MAIL_PRO_CRON="b3c678e4-15ea-41e3-a96d-da661c9c27c0"
MAIL_PERSON_CRON="568c5ad9-dcc7-4cec-95d6-7831fa4151ab"

for entry in "${NOTION_DBS[@]}"; do
  IFS='|' read -r api_key db_id label <<< "$entry"
  [[ -z "$api_key" ]] && continue

  STUCK_CARDS=$(curl -sS -X POST "https://api.notion.com/v1/databases/${db_id}/query" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{"filter":{"and":[{"property":"Status","status":{"equals":"Em andamento"}},{"property":"Tipo","select":{"equals":"OpenClaw"}}]}}' 2>/dev/null | python3 -c "
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
    while IFS='|' read -r page_id title agent mins; do
      log "[${label}] Card travado há ${mins}min: '${title}' (Agente=${agent})"
      report "⚠️ [${label}] Card '${title}' Em andamento há ${mins}min (Agente=${agent})"

      case "$agent" in
        Mail-Pro)
          log "Forçando execução do Mail-Pro..."
          openclaw cron run "${MAIL_PRO_CRON}" --timeout 5000 2>/dev/null &
          report "🔄 Forçado cron Mail-Pro para recuperação"
          ;;
        Mail-Person)
          log "Forçando execução do Mail-Person..."
          openclaw cron run "${MAIL_PERSON_CRON}" --timeout 5000 2>/dev/null &
          report "🔄 Forçado cron Mail-Person para recuperação"
          ;;
        *)
          if [[ "$mins" -gt 30 ]]; then
            report "🚨 Alerta: card '${title}' (Agente=${agent}) Em andamento há ${mins}min — intervenção manual"
          fi
          ;;
      esac
    done <<< "$STUCK_CARDS"
  else
    log "[${label}] Nenhum card travado"
  fi
done

# 5) Contagem final
TOTAL_CRONS=$(echo "$CRON_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
jobs = data.get('jobs', [])
enabled = sum(1 for j in jobs if j.get('enabled'))
print(f'{enabled}/{len(jobs)}')
" 2>/dev/null || echo "?/?")
report "📊 Crons habilitados: ${TOTAL_CRONS}"

# Output
echo ""
echo "=========================================="
echo " RELATÓRIO DE GOVERNANÇA"
echo " $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "=========================================="
echo -e "$REPORT"
echo "=========================================="
