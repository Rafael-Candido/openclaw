#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# notion-helper.sh — Helper para interações com Notion API
# Uso pelos agentes via exec para evitar problemas com JSON complexo em curl
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi

CMD="${1:-help}"
shift || true

notion_request() {
  local method="$1" url="$2" api_key="$3" body="${4:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer ${api_key}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer ${api_key}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json"
  fi
}

case "$CMD" in
  query)
    # Usage: notion-helper.sh query <db> <api_key_var> <agent_name> [status1] [status2]
    DB_ID="${1:?DB ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set: '"$API_KEY_VAR"'"}' && exit 1
    AGENT="${3:?Agent name required}"
    STATUS1="${4:-Priorizado}"
    STATUS2="${5:-Em andamento}"

    FILTER=$(python3 -c "
import json
f = {'and': [
    {'property': 'Tipo', 'select': {'equals': 'OpenClaw'}},
    {'property': 'Agente', 'select': {'equals': '$AGENT'}},
    {'or': [
        {'property': 'Status', 'select': {'equals': '$STATUS1'}},
        {'property': 'Status', 'select': {'equals': '$STATUS2'}}
    ]}
]}
print(json.dumps({'filter': f}))")

    notion_request POST "https://api.notion.com/v1/databases/${DB_ID}/query" "$API_KEY" "$FILTER"
    ;;

  update-status)
    # Usage: notion-helper.sh update-status <page_id> <api_key_var> <new_status>
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1
    NEW_STATUS="${3:?New status required}"

    BODY=$(python3 -c "import json; print(json.dumps({'properties': {'Status': {'select': {'name': '$NEW_STATUS'}}}}))")
    notion_request PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" "$API_KEY" "$BODY"
    ;;

  comment)
    # Usage: notion-helper.sh comment <page_id> <api_key_var> <message> [agente]
    # Se agente informado, prefixa o comentário com "[Agente] "
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1
    MESSAGE="${3:?Message required}"
    AGENTE="${4:-}"
    [[ -n "$AGENTE" ]] && MESSAGE="[$AGENTE] $MESSAGE"

    BODY=$(python3 -c "
import json
msg = '''$MESSAGE'''[:300]
print(json.dumps({
    'parent': {'page_id': '$PAGE_ID'},
    'rich_text': [{'type': 'text', 'text': {'content': msg}}]
}))")
    notion_request POST "https://api.notion.com/v1/comments" "$API_KEY" "$BODY"
    ;;

  get-page)
    # Usage: notion-helper.sh get-page <page_id> <api_key_var>
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1

    notion_request GET "https://api.notion.com/v1/pages/${PAGE_ID}" "$API_KEY"
    ;;

  get-blocks)
    # Usage: notion-helper.sh get-blocks <page_id> <api_key_var>
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1

    notion_request GET "https://api.notion.com/v1/blocks/${PAGE_ID}/children" "$API_KEY"
    ;;

  append-body)
    # Usage: notion-helper.sh append-body <page_id> <api_key_var> [file_path]
    # Se file_path omitido, lê de stdin. Adiciona blocos formatados (## heading, - item, 1. item).
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1
    if [[ -n "${3:-}" && -f "${3:-}" ]]; then
      INPUT="$(cat "$3")"
    else
      INPUT="$(cat)"
    fi
    BODY=$(echo "$INPUT" | python3 -c "
import json, sys, re
text = sys.stdin.read()
def esc(s):
    return s[:2000] if len(s) > 2000 else s
def mk_text(c):
    return [{'type': 'text', 'text': {'content': esc(c)}}]
blocks = []
for line in text.split('\n'):
    line = line.rstrip()
    if not line:
        continue
    if line.startswith('## '):
        blocks.append({'object': 'block', 'type': 'heading_2', 'heading_2': {'rich_text': mk_text(line[3:].strip())}})
    elif re.match(r'^[-*]\s+', line):
        blocks.append({'object': 'block', 'type': 'bulleted_list_item', 'bulleted_list_item': {'rich_text': mk_text(re.sub(r'^[-*]\s+', '', line))}})
    elif re.match(r'^\d+\.\s+', line):
        blocks.append({'object': 'block', 'type': 'numbered_list_item', 'numbered_list_item': {'rich_text': mk_text(re.sub(r'^\d+\.\s+', '', line))}})
    else:
        blocks.append({'object': 'block', 'type': 'paragraph', 'paragraph': {'rich_text': mk_text(line)}})
print(json.dumps({'children': blocks}))
" 2>/dev/null || echo '{"children":[]}')
    notion_request PATCH "https://api.notion.com/v1/blocks/${PAGE_ID}/children" "$API_KEY" "$BODY"
    ;;

  create-card)
    # Usage: notion-helper.sh create-card <db_id> <api_key_var> <title> [status] [tipo] [agente] [criador]
    # Se criador for informado, adiciona comentário: "Este card foi criado por: criador"
    DB_ID="${1:?DB ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1
    TITLE="${3:?Title required}"
    STATUS="${4:-Aguardando}"
    TIPO="${5:-OpenClaw}"
    AGENTE="${6:-Diretor Tech}"
    CRIADOR="${7:-}"

    BODY=$(python3 -c "
import json
print(json.dumps({
    'parent': {'database_id': '$DB_ID'},
    'properties': {
        'Name': {'title': [{'text': {'content': '''$TITLE'''}}]},
        'Status': {'select': {'name': '$STATUS'}},
        'Tipo': {'select': {'name': '$TIPO'}},
        'Agente': {'select': {'name': '$AGENTE'}}
    }
}))")
    RESPONSE=$(notion_request POST "https://api.notion.com/v1/pages" "$API_KEY" "$BODY")
    echo "$RESPONSE"
    if [[ -n "$CRIADOR" ]]; then
      PAGE_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)
      if [[ -n "$PAGE_ID" ]]; then
        BODY_CMD=$(python3 -c "
import json, sys
page_id, criador = sys.argv[1], sys.argv[2]
print(json.dumps({
    'parent': {'page_id': page_id},
    'rich_text': [{'type': 'text', 'text': {'content': 'Este card foi criado por: ' + criador}}]
}))" "$PAGE_ID" "$CRIADOR")
        notion_request POST "https://api.notion.com/v1/comments" "$API_KEY" "$BODY_CMD" >/dev/null 2>&1 || true
      fi
    fi
    ;;

  help|*)
    echo "notion-helper.sh — Notion API helper para agentes OpenClaw"
    echo ""
    echo "Comandos:"
    echo "  query <db_id> <api_key_var> <agent> [status1] [status2]"
    echo "  update-status <page_id> <api_key_var> <new_status>"
    echo "  comment <page_id> <api_key_var> <message> [agente]  # agente=assinatura no comentário"
    echo "  get-page <page_id> <api_key_var>"
    echo "  get-blocks <page_id> <api_key_var>"
    echo "  create-card <db_id> <api_key_var> <title> [status] [tipo] [agente] [criador]"
    echo "  append-body <page_id> <api_key_var> [file]  # lê de stdin se file omitido"
    echo ""
    echo "API Key Vars: NOTION_SMARTENVIOS_API_KEY, NOTION_PERSONAL_API_KEY, NOTION_CANPER_API_KEY"
    ;;
esac
