#!/bin/bash
set -e

# Script simples para interações com Notion API
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Carregar .env se existir
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi

ACTION="$1"
shift

case "$ACTION" in
  query)
    DB_ID="$1"
    AGENT="$2"
    STATUS="$3"
    API_KEY_VAR="$4"
    
    if [[ "$API_KEY_VAR" == "NOTION_PERSONAL_API_KEY" ]]; then
      API_KEY="${NOTION_PERSONAL_API_KEY}"
    elif [[ "$API_KEY_VAR" == "NOTION_SMARTENVIOS_API_KEY" ]]; then
      API_KEY="${NOTION_SMARTENVIOS_API_KEY}"
    elif [[ "$API_KEY_VAR" == "NOTION_CANPER_API_KEY" ]]; then
      API_KEY="${NOTION_CANPER_API_KEY}"
    else
      echo "{\"error\":\"API key var desconhecida: $API_KEY_VAR\"}" >&2
      exit 1
    fi
    
    if [[ -z "$API_KEY" ]]; then
      echo "{\"error\":\"API key não definida para $API_KEY_VAR\"}" >&2
      exit 1
    fi
    
    FILTER=$(python3 -c "
import json
f = {'and': [
    {'property': 'Tipo', 'select': {'equals': 'OpenClaw'}},
    {'property': 'Agente', 'select': {'equals': '$AGENT'}},
    {'property': 'Status', 'select': {'equals': '$STATUS'}}
]}
print(json.dumps({'filter': f}))")
    
    curl -s -X POST "https://api.notion.com/v1/databases/${DB_ID}/query" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      --data "$FILTER"
    ;;
    
  update-status)
    PAGE_ID="$1"
    NEW_STATUS="$2"
    API_KEY_VAR="$3"
    
    if [[ "$API_KEY_VAR" == "NOTION_PERSONAL_API_KEY" ]]; then
      API_KEY="${NOTION_PERSONAL_API_KEY}"
    elif [[ "$API_KEY_VAR" == "NOTION_SMARTENVIOS_API_KEY" ]]; then
      API_KEY="${NOTION_SMARTENVIOS_API_KEY}"
    elif [[ "$API_KEY_VAR" == "NOTION_CANPER_API_KEY" ]]; then
      API_KEY="${NOTION_CANPER_API_KEY}"
    else
      echo "{\"error\":\"API key var desconhecida: $API_KEY_VAR\"}" >&2
      exit 1
    fi
    
    if [[ -z "$API_KEY" ]]; then
      echo "{\"error\":\"API key não definida para $API_KEY_VAR\"}" >&2
      exit 1
    fi
    
    BODY=$(python3 -c "import json; print(json.dumps({'properties': {'Status': {'select': {'name': '$NEW_STATUS'}}}}))")
    
    curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      --data "$BODY"
    ;;
    
  comment)
    PAGE_ID="$1"
    MESSAGE="$2"
    AGENT="$3"
    API_KEY_VAR="$4"
    
    if [[ "$API_KEY_VAR" == "NOTION_PERSONAL_API_KEY" ]]; then
      API_KEY="${NOTION_PERSONAL_API_KEY}"
    elif [[ "$API_KEY_VAR" == "NOTION_SMARTENVIOS_API_KEY" ]]; then
      API_KEY="${NOTION_SMARTENVIOS_API_KEY}"
    elif [[ "$API_KEY_VAR" == "NOTION_CANPER_API_KEY" ]]; then
      API_KEY="${NOTION_CANPER_API_KEY}"
    else
      echo "{\"error\":\"API key var desconhecida: $API_KEY_VAR\"}" >&2
      exit 1
    fi
    
    if [[ -z "$API_KEY" ]]; then
      echo "{\"error\":\"API key não definida para $API_KEY_VAR\"}" >&2
      exit 1
    fi
    
    FULL_MESSAGE="[$AGENT] $MESSAGE"
    
    BODY=$(python3 -c "
import json
print(json.dumps({
    'parent': {'page_id': '$PAGE_ID'},
    'rich_text': {
        'rich_text': [{
            'type': 'text',
            'text': {'content': '$FULL_MESSAGE'}
        }]
    }
}))")
    
    curl -s -X POST "https://api.notion.com/v1/comments" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      --data "$BODY"
    ;;
    
  *)
    echo "{\"error\":\"Ação desconhecida: $ACTION\"}" >&2
    echo "Uso: $0 query <db_id> <agent> <status> <api_key_var>" >&2
    echo "     $0 update-status <page_id> <new_status> <api_key_var>" >&2
    echo "     $0 comment <page_id> <message> <agent> <api_key_var>" >&2
    exit 1
    ;;
esac