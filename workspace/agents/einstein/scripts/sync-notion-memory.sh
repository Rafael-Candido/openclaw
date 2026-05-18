#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_FILE="${AGENT_DIR}/MEMORY.md"
TMP_FILE="$(mktemp)"

cleanup() {
  rm -f "${TMP_FILE}"
}
trap cleanup EXIT

{
  echo "# MEMORY.md - Cache Bootstrap do Notion"
  echo
  echo "Gerado automaticamente a partir da base de conhecimento do Notion."
  echo "Este arquivo e apenas cache bootstrapado para contexto auxiliar."
  echo "A fonte de verdade continua sendo a API do Notion consultada em tempo de execucao."
  echo "Nao editar manualmente; rode \`scripts/sync-notion-memory.sh\` para atualizar."
  echo
  echo "- Fonte: bloco \`${EINSTEIN_NOTION_KB_BLOCK_ID:-2ed21016bd488033882be7b30727de5c}\`"
  echo "- Sincronizado em: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo
  "${SCRIPT_DIR}/notion-kb.sh" dump
} > "${TMP_FILE}"

mv "${TMP_FILE}" "${OUT_FILE}"
echo "${OUT_FILE}"
