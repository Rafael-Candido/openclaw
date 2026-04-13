#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo '{"ok":false,"error":"usage: handoff-suporte-software.sh <titulo> <descricao> [prioridade] [solicitante]"}'
  exit 1
fi

TITLE="$1"
DESCRIPTION="$2"
PRIORIDADE="${3:-Alta}"
SOLICITANTE="${4:-Einstein}"

case "$PRIORIDADE" in
  Alta|Média|Baixa) ;;
  *) PRIORIDADE="Alta" ;;
esac

ROOT_DIR="/var/www/openclaw/workspace"
HELPER="${ROOT_DIR}/scripts/notion-helper.sh"
DB_ID="adec12e735dc41a3bb7c274b287f3a10"
BODY_FILE="/tmp/einstein_handoff_suporte_$$.md"

if [[ -f /var/www/openclaw/.env ]]; then
  set +e +u
  # shellcheck disable=SC1091
  source /var/www/openclaw/.env >/dev/null 2>&1
  set -euo pipefail
fi

cat > "$BODY_FILE" <<BODY
## Solicitação recebida no atendimento
${DESCRIPTION}

## Handoff
- Origem: Einstein (Discord)
- Destino: Especialista de Suporte de Software
- Solicitante: ${SOLICITANTE}

## Objetivo
Investigar e resolver a demanda operacional de software com evidências objetivas e atualização no Jira/Notion quando aplicável.
BODY

NOTION_CACHE_ENABLED=false "$HELPER" create-card \
  "$DB_ID" \
  NOTION_SMARTENVIOS_API_KEY \
  "$TITLE" \
  "Priorizado" \
  "OpenClaw" \
  "Especialista de Suporte de Software" \
  "$PRIORIDADE" \
  "$SOLICITANTE" \
  "$BODY_FILE"

rm -f "$BODY_FILE" >/dev/null 2>&1 || true
