#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

read_env_var() {
  local key="$1"
  local file="$2"
  [[ -f "${file}" ]] || return 0
  local line
  line="$(grep -E "^${key}=" "${file}" | head -n 1 || true)"
  [[ -n "${line}" ]] || return 0
  local value="${line#*=}"
  if [[ "${value}" =~ ^\".*\"$ ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "${value}" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "${value}"
}

resolve_context_key() {
  local context="${1:-product}"
  case "${context}" in
    sales) printf '%s' "${N8N_SALES_API_KEY:-$(read_env_var N8N_SALES_API_KEY "${ENV_FILE}")}" ;;
    product) printf '%s' "${N8N_PRODUCT_API_KEY:-$(read_env_var N8N_PRODUCT_API_KEY "${ENV_FILE}")}" ;;
    finance) printf '%s' "${N8N_FINANCE_API_KEY:-$(read_env_var N8N_FINANCE_API_KEY "${ENV_FILE}")}" ;;
    success-client|sucess-client|customer-success) printf '%s' "${N8N_SUCESS_CLIENT_API_KEY:-$(read_env_var N8N_SUCESS_CLIENT_API_KEY "${ENV_FILE}")}" ;;
    support) printf '%s' "${N8N_SUPPORT_API_KEY:-$(read_env_var N8N_SUPPORT_API_KEY "${ENV_FILE}")}" ;;
    engineering|engineer) printf '%s' "${N8N_ENGINEERING_API_KEY:-$(read_env_var N8N_ENGINEERING_API_KEY "${ENV_FILE}")}" ;;
    marketing) printf '%s' "${N8N_MARKETING_API_KEY:-$(read_env_var N8N_MARKETING_API_KEY "${ENV_FILE}")}" ;;
    admin) printf '%s' "${N8N_ADMIN_API_KEY:-$(read_env_var N8N_ADMIN_API_KEY "${ENV_FILE}")}" ;;
    old|legacy) printf '%s' "${OLD_N8N_API_KEY:-$(read_env_var OLD_N8N_API_KEY "${ENV_FILE}")}" ;;
    *) printf '%s' "${N8N_API_KEY:-$(read_env_var N8N_API_KEY "${ENV_FILE}")}" ;;
  esac
}

CONTEXT="${N8N_CONTEXT:-$(read_env_var N8N_CONTEXT "${ENV_FILE}")}"
if [[ "${1:-}" == "--context" ]]; then
  CONTEXT="${2:-product}"
  shift 2
fi

N8N_MCP_URL="${N8N_MCP_URL:-$(read_env_var N8N_MCP_URL "${ENV_FILE}")}"
N8N_MCP_URL="${N8N_MCP_URL:-https://n8n.smartenvios.tec.br/mcp-server/http}"
N8N_MCP_BEARER_TOKEN="${N8N_MCP_BEARER_TOKEN:-$(read_env_var N8N_MCP_BEARER_TOKEN "${ENV_FILE}")}"
N8N_CONTEXT_API_KEY="$(resolve_context_key "${CONTEXT}")"
N8N_AUTH_TOKEN="${N8N_MCP_BEARER_TOKEN:-${N8N_CONTEXT_API_KEY:-}}"

usage() {
  cat <<USAGE
Uso:
  $0 [--context sales|product|finance|success-client|support|engineering|marketing|admin|old] tools
  $0 [--context sales|product|finance|success-client|support|engineering|marketing|admin|old] call <tool_name> '<json_args>'
USAGE
}

require_auth() {
  if [[ -z "${N8N_AUTH_TOKEN}" ]]; then
    echo "Erro: token ausente no .env para contexto '${CONTEXT}'" >&2
    exit 1
  fi
}

rpc_post() {
  local method="$1"
  local params="$2"
  local response

  response="$(curl -sS -X POST "${N8N_MCP_URL}" \
    -H "content-type: application/json" \
    -H "accept: application/json, text/event-stream" \
    -H "authorization:Bearer ${N8N_AUTH_TOKEN}" \
    -H "x-n8n-api-key: ${N8N_CONTEXT_API_KEY}" \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${method}\",\"params\":${params}}")"

  if [[ "${response}" == event:* || "${response}" == data:* ]]; then
    printf '%s\n' "${response}" | awk 'index($0,"data: ")==1{sub(/^data: /,""); print}' | tail -n 1
  else
    printf '%s\n' "${response}"
  fi
}

tools_list() {
  rpc_post "tools/list" "{}"
}

call_tool() {
  local tool_name="$1"
  local args_json="$2"
  rpc_post "tools/call" "{\"name\":\"${tool_name}\",\"arguments\":${args_json}}"
}

require_auth

cmd="${1:-}"
case "${cmd}" in
  tools)
    tools_list
    ;;
  call)
    if [[ $# -lt 3 ]]; then
      usage
      exit 1
    fi
    call_tool "$2" "$3"
    ;;
  *)
    usage
    exit 1
    ;;
esac
