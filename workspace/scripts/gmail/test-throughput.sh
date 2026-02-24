#!/usr/bin/env bash
# Script para testar throughput do Mail-Pro

set -euo pipefail

echo "=== Teste de Throughput Mail-Pro ==="
echo "Data: $(date)"
echo

# Carregar configurações
if [[ -f "/var/www/openclaw/workspace/scripts/gmail/batch-config.sh" ]]; then
  source "/var/www/openclaw/workspace/scripts/gmail/batch-config.sh" 2>/dev/null || true
fi

echo "Configurações atuais:"
echo "- MAIL_BATCH_MIN_LIMIT=${MAIL_BATCH_MIN_LIMIT:-10}"
echo "- MAIL_BATCH_MAX_LIMIT=${MAIL_BATCH_MAX_LIMIT:-30}"
echo "- MAIL_BATCH_STEP_UP=${MAIL_BATCH_STEP_UP:-5}"
echo "- MAIL_BATCH_STEP_DOWN=${MAIL_BATCH_STEP_DOWN:-5}"
echo "- MAIL_BACKLOG_EMERGENCY_THRESHOLD=${MAIL_BACKLOG_EMERGENCY_THRESHOLD:-40}"
echo "- MAIL_EMERGENCY_BATCH_LIMIT=${MAIL_EMERGENCY_BATCH_LIMIT:-25}"
echo

# Verificar backlog atual
echo "Verificando backlog atual..."
BACKLOG=$(/var/www/openclaw/workspace/scripts/gmail/gmail.sh pro list "is:unread in:inbox" 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)
echo "Backlog atual: $BACKLOG emails não lidos"
echo

# Verificar estado do batch
echo "Estado do batch adaptativo:"
if [[ -f "/tmp/openclaw-mail-pro-batch-state.json" ]]; then
  cat "/tmp/openclaw-mail-pro-batch-state.json" | jq .
else
  echo "Arquivo de estado não encontrado"
fi
echo

# Calcular throughput teórico
FREQUENCY_MIN=30  # minutos
MAX_LIMIT="${MAIL_BATCH_MAX_LIMIT:-30}"
EMERGENCY_LIMIT="${MAIL_EMERGENCY_BATCH_LIMIT:-25}"
EMERGENCY_THRESHOLD="${MAIL_BACKLOG_EMERGENCY_THRESHOLD:-40}"

THROUGHPUT_NORMAL=$((MAX_LIMIT * 60 / FREQUENCY_MIN))
THROUGHPUT_EMERGENCY=$((EMERGENCY_LIMIT * 60 / FREQUENCY_MIN))

echo "Throughput teórico:"
echo "- Modo normal: $THROUGHPUT_NORMAL emails/hora (limite $MAX_LIMIT, frequência ${FREQUENCY_MIN}min)"
echo "- Modo emergencial: $THROUGHPUT_EMERGENCY emails/hora (limite $EMERGENCY_LIMIT, frequência ${FREQUENCY_MIN}min)"
echo

# Verificar se está em modo emergencial
if (( BACKLOG >= EMERGENCY_THRESHOLD )); then
  echo "⚠️  BACKLOG ALTO ($BACKLOG >= $EMERGENCY_THRESHOLD)"
  echo "Sistema deve estar em modo emergencial"
  echo "Limite emergencial ativado: $EMERGENCY_LIMIT emails/batch"
else
  echo "✅ Backlog dentro do limite normal"
fi
echo

echo "=== Recomendações ==="
if (( BACKLOG > THROUGHPUT_NORMAL )); then
  echo "1. Backlog ($BACKLOG) > throughput normal ($THROUGHPUT_NORMAL emails/hora)"
  echo "   → Sistema já está em modo emergencial"
elif (( BACKLOG > (THROUGHPUT_NORMAL * 8 / 10) )); then
  echo "1. Backlog ($BACKLOG) próximo do throughput máximo"
  echo "   → Monitorar de perto"
else
  echo "1. Throughput suficiente para backlog atual"
fi

echo "2. Frequência atual: ${FREQUENCY_MIN} minutos"
echo "3. Próxima execução do cron: 7:17 AM"
echo "4. Última execução: 6:17 AM"
