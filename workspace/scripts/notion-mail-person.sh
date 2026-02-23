#!/bin/bash
set -e

# Script wrapper para notion-helper.sh com NOTION_PERSONAL_API_KEY pré-definida
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Carregar .env se existir
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi

if [[ -z "${NOTION_PERSONAL_API_KEY:-}" ]]; then
  echo "{\"error\":\"NOTION_PERSONAL_API_KEY não definida\"}" >&2
  exit 1
fi

# Executar notion-helper.sh com a API key
NOTION_API_KEY="${NOTION_PERSONAL_API_KEY}" "${SCRIPT_DIR}/notion-helper.sh" "$@"