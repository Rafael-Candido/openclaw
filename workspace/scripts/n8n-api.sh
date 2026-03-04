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

normalize_base_url() {
  local raw="${1:-}"
  raw="${raw%/}"
  [[ -n "${raw}" ]] || return 0
  if [[ "${raw}" == */api/v1 ]]; then
    printf '%s' "${raw}"
  else
    printf '%s/api/v1' "${raw}"
  fi
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

resolve_context_url() {
  local context="${1:-product}"
  local base=""
  case "${context}" in
    old|legacy)
      base="${OLD_N8N_URL:-$(read_env_var OLD_N8N_URL "${ENV_FILE}")}"
      ;;
    *)
      base="${N8N_API_BASE_URL:-$(read_env_var N8N_API_BASE_URL "${ENV_FILE}")}"
      [[ -z "${base}" ]] && base="https://n8n.smartenvios.tec.br/api/v1"
      ;;
  esac
  normalize_base_url "${base}"
}

CONTEXT="${N8N_CONTEXT:-product}"
if [[ "${1:-}" == "--context" ]]; then
  CONTEXT="${2:-product}"
  shift 2
fi

N8N_API_BASE_URL="$(resolve_context_url "${CONTEXT}")"
N8N_API_KEY="$(resolve_context_key "${CONTEXT}")"

usage() {
  cat <<USAGE
Uso:
  $0 [--context sales|product|finance|success-client|support|engineering|marketing|admin|old] get <workflow_id>
  $0 [--context sales|product|finance|success-client|support|engineering|marketing|admin|old] put <workflow_id> <payload_json_file>
  $0 [--context sales|product|finance|success-client|support|engineering|marketing|admin|old] can-write <workflow_id>

Exemplos:
  $0 --context product get gj2LbZNwFi2h9TiR3cJJa
  $0 --context finance put gj2LbZNwFi2h9TiR3cJJa /tmp/payload.json
  $0 --context sales can-write gj2LbZNwFi2h9TiR3cJJa
USAGE
}

require_auth() {
  if [[ -z "${N8N_API_KEY}" ]]; then
    echo "Erro: API key ausente para contexto '${CONTEXT}' no .env" >&2
    exit 1
  fi
  if [[ -z "${N8N_API_BASE_URL}" ]]; then
    echo "Erro: URL base ausente para contexto '${CONTEXT}'" >&2
    exit 1
  fi
}

get_workflow() {
  local workflow_id="$1"
  curl -sS \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_API_BASE_URL}/workflows/${workflow_id}"
}

put_workflow() {
  local workflow_id="$1"
  local payload_file="$2"
  local http_code
  http_code="$(curl -sS -o /tmp/n8n_api_put_resp_${workflow_id}.json -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_API_BASE_URL}/workflows/${workflow_id}" \
    --data @"${payload_file}")"
  echo "${http_code}"
}

can_write() {
  local workflow_id="$1"
  local wf_file payload_file http_code
  wf_file="/tmp/n8n_api_get_${workflow_id}.json"
  payload_file="/tmp/n8n_api_put_${workflow_id}.json"

  get_workflow "${workflow_id}" > "${wf_file}"
  jq '{name,nodes,connections,settings:{executionOrder:(.settings.executionOrder // "v1")}}' "${wf_file}" > "${payload_file}"
  http_code="$(put_workflow "${workflow_id}" "${payload_file}")"

  jq -n \
    --arg wf "${workflow_id}" \
    --arg hc "${http_code}" \
    --arg ctx "${CONTEXT}" \
    --arg url "${N8N_API_BASE_URL}" \
    '{workflow_id:$wf,context:$ctx,api_base_url:$url,http_code:($hc|tonumber),can_write:($hc=="200")}'
}

require_auth

cmd="${1:-}"
case "${cmd}" in
  get)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    get_workflow "$2"
    ;;
  put)
    [[ $# -eq 3 ]] || { usage; exit 1; }
    put_workflow "$2" "$3"
    ;;
  can-write)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    can_write "$2"
    ;;
  *)
    usage
    exit 1
    ;;
esac
