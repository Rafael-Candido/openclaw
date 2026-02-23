#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# notion-helper.sh — Helper para interações com Notion API
# Uso pelos agentes via exec para evitar problemas com JSON complexo em curl
# 
# Melhorias de resiliência a rate limits (2026-02-22):
# - Retry automático para erros 429 (rate limit) e 5xx
# - Backoff exponencial com jitter entre tentativas
# - Logging detalhado de tentativas
# - Configuração de limites de tentativas
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configurações de resiliência
NOTION_MAX_RETRIES="${NOTION_MAX_RETRIES:-3}"
NOTION_BASE_DELAY="${NOTION_BASE_DELAY:-2}"  # segundos
NOTION_ENABLE_LOGGING="${NOTION_ENABLE_LOGGING:-true}"
NOTION_MAX_JITTER="${NOTION_MAX_JITTER:-3}"  # segundos
NOTION_CURL_TIMEOUT="${NOTION_CURL_TIMEOUT:-30}"  # segundos
NOTION_CACHE_ENABLED="${NOTION_CACHE_ENABLED:-true}"
NOTION_CACHE_TTL="${NOTION_CACHE_TTL:-300}"  # 5 minutos em segundos

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi

# Inicializar diretório de cache
CACHE_DIR="${PROJECT_ROOT}/.cache/notion"
mkdir -p "$CACHE_DIR"

# Função de logging condicional
notion_log() {
  if [[ "$NOTION_ENABLE_LOGGING" == "true" ]]; then
    echo "{\"log\":\"notion-helper: $1\"}" >&2
  fi
}

# Função para gerar hash de cache
notion_cache_hash() {
  echo -n "$1" | openssl md5 | cut -d' ' -f2
}

# Função para verificar cache
notion_cache_get() {
  local key="$1"
  local hash
  hash=$(notion_cache_hash "$key")
  local cache_file="$CACHE_DIR/$hash"
  
  if [[ "$NOTION_CACHE_ENABLED" != "true" ]]; then
    return 1
  fi
  
  if [[ -f "$cache_file" ]]; then
    local cache_age
    cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)))
    
    if [[ $cache_age -lt $NOTION_CACHE_TTL ]]; then
      cat "$cache_file"
      notion_log "cache hit for $key (age: ${cache_age}s)"
      return 0
    else
      notion_log "cache expired for $key (age: ${cache_age}s > ${NOTION_CACHE_TTL}s)"
      rm -f "$cache_file"
    fi
  fi
  return 1
}

# Função para salvar no cache
notion_cache_set() {
  local key="$1"
  local data="$2"
  local hash
  hash=$(notion_cache_hash "$key")
  local cache_file="$CACHE_DIR/$hash"
  
  if [[ "$NOTION_CACHE_ENABLED" == "true" ]]; then
    echo "$data" > "$cache_file"
    notion_log "cache set for $key"
  fi
}

CMD="${1:-help}"
shift || true

notion_request() {
  local method="$1" url="$2" api_key="$3" body="${4:-}"
  local max_retries="$NOTION_MAX_RETRIES"
  local base_delay="$NOTION_BASE_DELAY"
  local attempt=0
  local response=""
  local http_code=0
  
  notion_log "iniciando request $method $url (max_retries=$max_retries)"
  
  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))
    
    # Construir comando curl com timeout
    local curl_cmd="curl -sS -w '\n%{http_code}' --max-time '$NOTION_CURL_TIMEOUT' -X '$method' '$url' \
      -H 'Authorization: Bearer $api_key' \
      -H 'Notion-Version: 2022-06-28' \
      -H 'Content-Type: application/json'"
    
    if [[ -n "$body" ]]; then
      curl_cmd="$curl_cmd -d '$body'"
    fi
    
    # Executar curl e capturar resposta + código HTTP
    local curl_output=""
    curl_output=$(eval "$curl_cmd" 2>/dev/null || echo "CURL_ERROR")
    
    if [[ "$curl_output" == "CURL_ERROR" ]]; then
      http_code=0
      response="{\"error\":\"curl command failed\"}"
    else
      # Extrair código HTTP (última linha) e resposta (todas exceto última)
      http_code=$(echo "$curl_output" | tail -n 1)
      response=$(echo "$curl_output" | sed '$d')
    fi
    
    # Log da tentativa
    if [[ $attempt -gt 1 ]]; then
      notion_log "request attempt $attempt/$max_retries for $method $url"
    fi
    
    # Verificar se foi bem-sucedido
    if [[ $http_code -eq 200 ]] || [[ $http_code -eq 201 ]] || [[ $http_code -eq 204 ]]; then
      notion_log "request successful (HTTP $http_code) for $method $url"
      echo "$response"
      return 0
    fi
    
    # Verificar se é rate limit (429) ou erro temporário (5xx)
    if [[ $http_code -eq 429 ]] || [[ $http_code -ge 500 ]]; then
      # Calcular backoff exponencial com jitter
      local delay=$((base_delay * (2 ** (attempt - 1))))
      local jitter=$((RANDOM % NOTION_MAX_JITTER + 1))  # Jitter aleatório
      delay=$((delay + jitter))
      
      notion_log "HTTP $http_code, retrying in ${delay}s (attempt $attempt/$max_retries) for $method $url"
      sleep "$delay"
    else
      # Erro não recuperável (4xx exceto 429)
      notion_log "HTTP $http_code, not retrying (non-retryable error) for $method $url"
      echo "$response"
      return 1
    fi
  done
  
  # Todas as tentativas falharam
  notion_log "failed after $max_retries attempts for $method $url"
  echo "$response"
  return 1
}

normalize_notion_priority() {
  local raw="${1:-}"
  local value
  value="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    alta|high|highest|critical|critica|crítica)
      echo "Alta"
      return 0
      ;;
    media|média|medium|normal|moderada|moderado)
      echo "Média"
      return 0
      ;;
    baixa|low|lowest)
      echo "Baixa"
      return 0
      ;;
  esac
  return 1
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

    # Gerar chave de cache
    CACHE_KEY="query:${DB_ID}:${AGENT}:${STATUS1}:${STATUS2}"
    
    # Tentar obter do cache primeiro
    CACHED_RESPONSE=$(notion_cache_get "$CACHE_KEY" || true)
    if [[ -n "$CACHED_RESPONSE" ]]; then
      echo "$CACHED_RESPONSE"
      exit 0
    fi

    FILTER=$(python3 -c "
import json
f = {'and': [
    {'property': 'Tipo', 'select': {'equals': 'OpenClaw'}},
    *([{'property': 'Agente', 'select': {'is_empty': True}}] if '$AGENT' == 'UNASSIGNED' else [{'property': 'Agente', 'select': {'equals': '$AGENT'}}]),
    {'or': [
        {'property': 'Status', 'select': {'equals': '$STATUS1'}},
        {'property': 'Status', 'select': {'equals': '$STATUS2'}}
    ]}
]}
print(json.dumps({'filter': f}))")

    RESPONSE=$(notion_request POST "https://api.notion.com/v1/databases/${DB_ID}/query" "$API_KEY" "$FILTER")
    
    # Salvar no cache se a resposta for válida
    if echo "$RESPONSE" | grep -q '"object":"list"'; then
      notion_cache_set "$CACHE_KEY" "$RESPONSE"
    fi
    
    echo "$RESPONSE"
    ;;

  update-status)
    # Usage: notion-helper.sh update-status <page_id> <api_key_var> <new_status>
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{\"error\":\"API key not set\"}' && exit 1
    NEW_STATUS="${3:?New status required}"

    BODY=$(python3 -c "import json; print(json.dumps({'properties': {'Status': {'select': {'name': '$NEW_STATUS'}}}}))")
    RESPONSE=$(notion_request PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" "$API_KEY" "$BODY")
    
    # Limpar cache após atualização
    notion_log "clearing cache after status update"
    rm -f "$CACHE_DIR"/* 2>/dev/null || true
    
    echo "$RESPONSE"
    ;;

  update-agent)
    # Usage: notion-helper.sh update-agent <page_id> <api_key_var> <agent_name>
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{\"error\":\"API key not set\"}' && exit 1
    NEW_AGENT="${3:?Agent name required}"

    BODY=$(python3 -c "import json; print(json.dumps({'properties': {'Agente': {'select': {'name': '$NEW_AGENT'}}}}))")
    RESPONSE=$(notion_request PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" "$API_KEY" "$BODY")
    
    # Limpar cache após atualização
    notion_log "clearing cache after agent update"
    rm -f "$CACHE_DIR"/* 2>/dev/null || true
    
    echo "$RESPONSE"
    ;;

  update-priority)
    # Usage: notion-helper.sh update-priority <page_id> <api_key_var> <priority>
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1
    RAW_PRIORITY="${3:?Priority required}"

    PRIORIDADE="$(normalize_notion_priority "$RAW_PRIORITY" || true)"
    if [[ -z "${PRIORIDADE:-}" ]]; then
      echo "{\"error\":\"invalid priority: ${RAW_PRIORITY}\"}"
      exit 1
    fi

    BODY=$(python3 -c "import json; print(json.dumps({'properties': {'Prioridade': {'select': {'name': '$PRIORIDADE'}}}}))")
    RESPONSE=$(notion_request PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" "$API_KEY" "$BODY")

    notion_log "clearing cache after priority update"
    rm -f "$CACHE_DIR"/* 2>/dev/null || true

    echo "$RESPONSE"
    ;;

  comment)
    # Usage: notion-helper.sh comment <page_id> <api_key_var> <message> [agente]
    # agente (4º param) OBRIGATÓRIO: assinatura no Notion; prefixa "[Agente] ". Máx 2000 chars.
    PAGE_ID="${1:?Page ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{\"error\":\"API key not set\"}' && exit 1
    MESSAGE="${3:?Message required}"
    AGENTE="${4:-}"
    [[ -n "$AGENTE" ]] && MESSAGE="[$AGENTE] $MESSAGE"

    # Dedupe anti-spam: não repete comentário idêntico já existente no card.
    DUPLICATE=$(python3 - "$PAGE_ID" "$API_KEY" "$MESSAGE" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

page_id, api_key, message = sys.argv[1], sys.argv[2], sys.argv[3]

def norm(s: str) -> str:
    return " ".join((s or "").strip().split())

target = norm(message)
headers = {
    "Authorization": f"Bearer {api_key}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}

next_cursor = None
for _ in range(3):
    url = f"https://api.notion.com/v1/comments?block_id={urllib.parse.quote(page_id)}"
    if next_cursor:
        url += f"&start_cursor={urllib.parse.quote(next_cursor)}"
    try:
        req = urllib.request.Request(url, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        # Em caso de falha na leitura, não bloqueia comentário.
        print("no")
        sys.exit(0)

    for comment in data.get("results", []):
        txt = "".join(rt.get("plain_text", "") for rt in comment.get("rich_text", []))
        if norm(txt) == target:
            print("yes")
            sys.exit(0)

    if not data.get("has_more"):
        break
    next_cursor = data.get("next_cursor")

print("no")
PY
)
    if [[ "${DUPLICATE}" == "yes" ]]; then
      echo '{"ok":true,"skipped":true,"reason":"duplicate-comment"}'
      exit 0
    fi

    BODY=$(python3 -c "
import json
msg = '''$MESSAGE'''[:2000]
print(json.dumps({
    'parent': {'page_id': '$PAGE_ID'},
    'rich_text': [{'type': 'text', 'text': {'content': msg}}]
}))")
    RESPONSE=$(notion_request POST "https://api.notion.com/v1/comments" "$API_KEY" "$BODY")
    
    # Limpar cache após comentário (pode indicar mudança no card)
    notion_log "clearing cache after comment"
    rm -f "$CACHE_DIR"/* 2>/dev/null || true
    
    echo "$RESPONSE"
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
    # Usage:
    #   notion-helper.sh create-card <db_id> <api_key_var> <title> [status] [tipo] [agente] [criador] [body_file]
    #   notion-helper.sh create-card <db_id> <api_key_var> <title> [status] [tipo] [agente] [prioridade] [criador] [body_file]
    # Prioridade aceita: Alta|Média|Baixa (ou aliases high/medium/low).
    # Também pode vir via env: NOTION_CARD_PRIORITY
    # Se criador informado, adiciona comentário "Este card foi criado por: criador"
    # Se body_file informado (caminho de arquivo), adiciona o conteúdo como descrição do card
    DB_ID="${1:?DB ID required}"
    API_KEY_VAR="${2:?API key var required}"
    API_KEY="${!API_KEY_VAR:-}"
    [[ -z "$API_KEY" ]] && echo '{"error":"API key not set"}' && exit 1
    TITLE="${3:?Title required}"
    STATUS="${4:-Aguardando}"
    TIPO="${5:-OpenClaw}"
    AGENTE="${6:-Diretor Tech}"
    EXTRA1="${7:-}"
    EXTRA2="${8:-}"
    EXTRA3="${9:-}"

    PRIORIDADE_RAW="${NOTION_CARD_PRIORITY:-}"
    CRIADOR=""
    BODY_FILE=""

    if normalize_notion_priority "${EXTRA1:-}" >/dev/null 2>&1; then
      PRIORIDADE_RAW="${EXTRA1}"
      CRIADOR="${EXTRA2:-}"
      BODY_FILE="${EXTRA3:-}"
    else
      CRIADOR="${EXTRA1:-}"
      BODY_FILE="${EXTRA2:-}"
      if [[ -n "${EXTRA3:-}" ]]; then
        PRIORIDADE_RAW="${EXTRA3}"
      fi
    fi

    PRIORIDADE="$(normalize_notion_priority "${PRIORIDADE_RAW:-}" || true)"
    if [[ -z "${PRIORIDADE:-}" ]]; then
      case "${STATUS}" in
        Priorizado|priorizado)
          PRIORIDADE="Média"
          ;;
        Aguardando|aguardando)
          PRIORIDADE="Baixa"
          ;;
      esac
    fi

    BODY_CONTENT=""
    if [[ -n "${BODY_FILE:-}" && -f "${BODY_FILE:-}" ]]; then
      BODY_CONTENT="$(cat "${BODY_FILE}")"
    fi

    # Guardrail: cards do Engenheiro de Prompt precisam nascer com descrição mínima.
    if [[ "$AGENTE" == "Engenheiro de Prompt" ]]; then
      if [[ -z "${BODY_FILE:-}" || ! -f "${BODY_FILE:-}" ]]; then
        echo '{"error":"body_file_required_for_eng_prompt","message":"Cards para Engenheiro de Prompt exigem body_file com descrição técnica."}'
        exit 1
      fi
      if [[ -z "${BODY_CONTENT//[[:space:]]/}" ]]; then
        echo '{"error":"body_file_empty_for_eng_prompt","message":"body_file está vazio; descrição técnica obrigatória para Engenheiro de Prompt."}'
        exit 1
      fi
    fi

    BODY=$(python3 - "$DB_ID" "$TITLE" "$STATUS" "$TIPO" "$AGENTE" "${PRIORIDADE:-}" "$BODY_CONTENT" <<'PY'
import json
import sys
import re

db_id, title, status, tipo, agente, prioridade, body_text = sys.argv[1:8]
props = {
    "Name": {"title": [{"text": {"content": title}}]},
    "Status": {"select": {"name": status}},
    "Tipo": {"select": {"name": tipo}},
    "Agente": {"select": {"name": agente}},
}
if prioridade:
    props["Prioridade"] = {"select": {"name": prioridade}}

payload = {
    "parent": {"database_id": db_id},
    "properties": props,
}

def esc(s: str) -> str:
    return s[:2000] if len(s) > 2000 else s

def mk_text(content: str):
    return [{"type": "text", "text": {"content": esc(content)}}]

children = []
for raw in (body_text or "").split("\n"):
    line = raw.rstrip()
    if not line:
      continue
    if line.startswith("## "):
      children.append({"object": "block", "type": "heading_2", "heading_2": {"rich_text": mk_text(line[3:].strip())}})
    elif re.match(r"^[-*]\s+", line):
      children.append({"object": "block", "type": "bulleted_list_item", "bulleted_list_item": {"rich_text": mk_text(re.sub(r"^[-*]\s+", "", line))}})
    elif re.match(r"^\d+\.\s+", line):
      children.append({"object": "block", "type": "numbered_list_item", "numbered_list_item": {"rich_text": mk_text(re.sub(r"^\d+\.\s+", "", line))}})
    else:
      children.append({"object": "block", "type": "paragraph", "paragraph": {"rich_text": mk_text(line)}})

if children:
    payload["children"] = children

print(json.dumps(payload, ensure_ascii=False))
PY
)
    RESPONSE=$(notion_request POST "https://api.notion.com/v1/pages" "$API_KEY" "$BODY")
    echo "$RESPONSE"
    PAGE_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)
    if [[ -n "$PAGE_ID" ]]; then
      if [[ -n "$CRIADOR" ]]; then
        BODY_CMD=$(python3 -c "
import json, sys
page_id, criador = sys.argv[1], sys.argv[2]
print(json.dumps({
    'parent': {'page_id': page_id},
    'rich_text': [{'type': 'text', 'text': {'content': 'Este card foi criado por: ' + criador}}]
}))" "$PAGE_ID" "$CRIADOR")
        notion_request POST "https://api.notion.com/v1/comments" "$API_KEY" "$BODY_CMD" >/dev/null 2>&1 || true
      fi
      :
    fi
    ;;

  help|*)
    echo "notion-helper.sh — Notion API helper para agentes OpenClaw"
    echo ""
    echo "Comandos:"
    echo "  query <db_id> <api_key_var> <agent> [status1] [status2]"
    echo "  update-status <page_id> <api_key_var> <new_status>"
    echo "  update-agent <page_id> <api_key_var> <new_agent>"
    echo "  update-priority <page_id> <api_key_var> <priority>"
    echo "  comment <page_id> <api_key_var> <message> [agente]  # agente (4º)=assinatura OBRIGATÓRIA, máx 2000 chars"
    echo "  get-page <page_id> <api_key_var>"
    echo "  get-blocks <page_id> <api_key_var>"
    echo "  create-card <db_id> <api_key_var> <title> [status] [tipo] [agente] [criador] [body_file]"
    echo "  create-card <db_id> <api_key_var> <title> [status] [tipo] [agente] [prioridade] [criador] [body_file]"
    echo "    Regra: para agente 'Engenheiro de Prompt', body_file é obrigatório e não pode estar vazio."
    echo "  append-body <page_id> <api_key_var> [file]  # lê de stdin se file omitido"
    echo ""
    echo "API Key Vars: NOTION_SMARTENVIOS_API_KEY, NOTION_PERSONAL_API_KEY, NOTION_CANPER_API_KEY"
    echo ""
    echo "Configurações de resiliência (variáveis de ambiente):"
    echo "  NOTION_MAX_RETRIES=3       # Máximo de tentativas para rate limits"
    echo "  NOTION_BASE_DELAY=2        # Delay base para backoff exponencial (segundos)"
    echo "  NOTION_MAX_JITTER=3        # Jitter máximo para evitar thundering herd"
    echo "  NOTION_CURL_TIMEOUT=30     # Timeout para requests curl (segundos)"
    echo "  NOTION_ENABLE_LOGGING=true # Habilitar logging detalhado"
    echo "  NOTION_CACHE_ENABLED=true  # Habilitar cache de queries"
    echo "  NOTION_CACHE_TTL=300       # TTL do cache em segundos (5 minutos)"
    echo ""
    echo "Recursos de resiliência:"
    echo "  • Retry automático para erros 429 (rate limit) e 5xx"
    echo "  • Backoff exponencial com jitter aleatório"
    echo "  • Logging detalhado de tentativas"
    echo "  • Timeout configurável para requests"
    echo "  • Cache de queries para reduzir chamadas à API"
    echo "  • Limpeza automática de cache após atualizações"
    echo ""
    echo "Exemplo de configuração:"
    echo "  export NOTION_MAX_RETRIES=5"
    echo "  export NOTION_BASE_DELAY=3"
    echo "  export NOTION_ENABLE_LOGGING=false"
    ;;
esac
