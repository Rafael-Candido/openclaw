#!/usr/bin/env bash
# Script de fallback simples para Mail-Pro quando o sistema principal falha

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMAIL_SCRIPT="${SCRIPT_DIR}/gmail.sh"
LOG_FILE="/tmp/openclaw-mail-${PROFILE}-simple.log"

# Função de logging
log() {
  echo "{\"log\":\"process-simple: $1\"}" >&2
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log "starting simple fallback for profile $PROFILE with limit $LIMIT"

# Verificar se script existe
if [[ ! -x "$GMAIL_SCRIPT" ]]; then
  log "error: gmail script not found: $GMAIL_SCRIPT"
  echo '{"error":"gmail script not found","profile":"'"$PROFILE"'","limit":"'"$LIMIT"'"}'
  exit 1
fi

# Operação básica: marcar como lido e arquivar
log "fetching unread emails"
UNREAD_LIST=$("$GMAIL_SCRIPT" "$PROFILE" list "is:unread in:inbox" 2>/dev/null || echo '{"messages":[]}')

# Extrair IDs de mensagens
MESSAGE_IDS=$(echo "$UNREAD_LIST" | jq -r '.messages[].id // empty' 2>/dev/null || echo "")

if [[ -z "$MESSAGE_IDS" ]]; then
  log "no unread emails found"
  echo '{"result":"no unread emails","profile":"'"$PROFILE"'","processed":0}'
  exit 0
fi

# Limitar número de emails
COUNT=0
PROCESSED_IDS=()

for MSG_ID in $MESSAGE_IDS; do
  if [[ $COUNT -ge $LIMIT ]]; then
    break
  fi
  
  log "processing message $MSG_ID"
  
  # Marcar como lido
  "$GMAIL_SCRIPT" "$PROFILE" mark-read "$MSG_ID" 2>/dev/null || true
  
  # Arquivar
  "$GMAIL_SCRIPT" "$PROFILE" archive "$MSG_ID" 2>/dev/null || true
  
  PROCESSED_IDS+=("$MSG_ID")
  COUNT=$((COUNT + 1))
  
  # Pequena pausa para evitar rate limits
  sleep 0.5
done

log "processed $COUNT emails"
echo '{"result":"success","profile":"'"$PROFILE"'","processed":'"$COUNT"',"messageIds":'"$(echo "${PROCESSED_IDS[@]}" | jq -R 'split(" ")')"'}'
exit 0