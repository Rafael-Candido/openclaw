#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

N8N_MCP_URL="${N8N_MCP_URL:-https://n8n.smartenvios.tec.br/mcp-server/http}"
N8N_MCP_BEARER_TOKEN="${N8N_MCP_BEARER_TOKEN:-}"

usage() {
  cat <<USAGE
Uso:
  $0 tools
  $0 call <tool_name> '<json_args>'

Exemplos:
  $0 tools
  $0 call search_workflows '{"limit":10,"query":"crm"}'
  $0 call get_workflow_details '{"workflowId":"abc123"}'
USAGE
}

require_auth() {
  if [[ -z "${N8N_MCP_BEARER_TOKEN}" ]]; then
    echo "Erro: N8N_MCP_BEARER_TOKEN ausente no .env" >&2
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
    -H "authorization:Bearer ${N8N_MCP_BEARER_TOKEN}" \
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
