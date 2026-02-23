#!/usr/bin/env bash
# Wrapper com timeout para process-notion-cards.sh

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-15}"
TIMEOUT_SEC="${PROCESS_TIMEOUT_SEC:-300}"  # 5 minutos padrão
SAFE_MODE="${SAFE_MODE:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROCESS_SCRIPT="${SCRIPT_DIR}/process-notion-cards.sh"
LOG_FILE="/tmp/openclaw-mail-${PROFILE}-process.log"
PID_FILE="/tmp/openclaw-mail-${PROFILE}-process.pid"

# Função de logging
log() {
  echo "{\"log\":\"process-with-timeout: $1\"}" >&2
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Função para matar processo e filhos
kill_tree() {
  local pid="$1"
  log "killing process tree for PID $pid"
  
  # Matar grupo de processos
  kill -9 "$pid" 2>/dev/null || true
  
  # Matar processos filhos
  pkill -P "$pid" 2>/dev/null || true
  
  # Limpar PID file
  rm -f "$PID_FILE"
}

# Verificar se script existe
if [[ ! -x "$PROCESS_SCRIPT" ]]; then
  log "error: process script not found: $PROCESS_SCRIPT"
  echo '{"error":"process script not found"}'
  exit 1
fi

# Modo seguro: limite reduzido e skip de operações complexas
if [[ "$SAFE_MODE" == "true" ]]; then
  log "safe mode enabled - using reduced limit 5"
  LIMIT="5"
  export MAIL_SAFE_MODE="true"
fi

# Iniciar processo em background
log "starting process for profile $PROFILE with limit $LIMIT (timeout: ${TIMEOUT_SEC}s)"
"$PROCESS_SCRIPT" "$PROFILE" "$LIMIT" &
PROCESS_PID=$!

# Salvar PID
echo "$PROCESS_PID" > "$PID_FILE"
log "process started with PID $PROCESS_PID"

# Aguardar com timeout
TIMEOUT_REACHED=false
for ((i=0; i<TIMEOUT_SEC; i++)); do
  if ! kill -0 "$PROCESS_PID" 2>/dev/null; then
    # Processo terminou
    wait "$PROCESS_PID" || true
    EXIT_CODE=$?
    log "process completed with exit code $EXIT_CODE"
    rm -f "$PID_FILE"
    
    # Se falhou no modo normal, tentar modo seguro
    if [[ $EXIT_CODE -ne 0 ]] && [[ "$SAFE_MODE" != "true" ]]; then
      log "process failed, retrying in safe mode"
      export SAFE_MODE="true"
      exec "$0" "$PROFILE" "$LIMIT"
    fi
    
    exit $EXIT_CODE
  fi
  sleep 1
done

# Timeout atingido
log "timeout reached after ${TIMEOUT_SEC} seconds"
TIMEOUT_REACHED=true

# Matar processo
kill_tree "$PROCESS_PID"

# Se não estava em modo seguro, tentar modo seguro
if [[ "$SAFE_MODE" != "true" ]]; then
  log "retrying in safe mode after timeout"
  export SAFE_MODE="true"
  exec "$0" "$PROFILE" "$LIMIT"
else
  # Já estava em modo seguro e ainda timeout
  log "timeout even in safe mode - system may be overloaded"
  echo '{"error":"timeout even in safe mode","profile":"'"$PROFILE"'","limit":"'"$LIMIT"'","safeMode":true}'
  exit 124
fi