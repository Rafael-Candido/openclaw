#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
STATE_DIR="${PROJECT_ROOT}/workspace/.state"
TOKEN_FILE="${STATE_DIR}/smartenvios_mcp_session_token"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

MCP_URL="${SMARTENVIOS_MCP_URL:-https://staging.smartenvios.tec.br/mcp}"
MCP_EMAIL="${SMARTENVIOS_MCP_EMAIL:-}"
MCP_PASSWORD="${SMARTENVIOS_MCP_PASSWORD:-}"

mkdir -p "${STATE_DIR}"

usage() {
  cat <<EOF
Uso:
  $0 login
  $0 tools
  $0 call <tool_name> '<json_args>'

Exemplos:
  $0 login
  $0 tools
  $0 call smartenvios_quote_freight '{"zip_code_start":"14020510","zip_code_end":"01305100","volumes":[{"quantity":1,"length":20,"height":10,"weight":1,"width":15}, "timeout": 5000}'  # Added timeout for CEP calls to improve performance
EOF
}

rpc_post() {
  local method="$1"
  local params="$2"
  python3 - "$MCP_URL" "$method" "$params" <<'PY'
import json, sys, urllib.request
url = sys.argv[1]
method = sys.argv[2]
params = json.loads(sys.argv[3])
payload = {"jsonrpc":"2.0","id":1,"method":method,"params":params}
req = urllib.request.Request(
    url,
    data=json.dumps(payload).encode(),
    headers={"Content-Type":"application/json"}
)
with urllib.request.urlopen(req, timeout=45) as resp:
    print(resp.read().decode())
PY
}

login() {
  if [[ -z "${MCP_EMAIL}" || -z "${MCP_PASSWORD}" ]]; then
    echo "Erro: SMARTENVIOS_MCP_EMAIL/SMARTENVIOS_MCP_PASSWORD ausentes no .env" >&2
    exit 1
  fi

  local result
  result="$(rpc_post "tools/call" "{\"name\":\"auth_login\",\"arguments\":{\"email\":\"${MCP_EMAIL}\",\"password\":\"${MCP_PASSWORD}\"}}")"

  local token
  token="$(python3 - <<'PY' "${result}"
import json,sys,re
obj=json.loads(sys.argv[1])
texts=[]
for c in obj.get("result",{}).get("content",[]):
    if c.get("type")=="text":
        texts.append(c.get("text",""))
joined="\n".join(texts)
m=re.search(r'"session_token"\s*:\s*"([^"]+)"', joined)
if not m:
    m=re.search(r'session_token[=:]\s*([A-Za-z0-9._-]+)', joined)
print(m.group(1) if m else "")
PY
)"

  if [[ -z "${token}" ]]; then
    echo "Erro: não foi possível extrair session_token do auth_login" >&2
    echo "${result}" >&2
    exit 1
  fi

  printf "%s" "${token}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  echo "Login OK. session_token salvo em ${TOKEN_FILE}"
}

ensure_token() {
  if [[ ! -f "${TOKEN_FILE}" ]]; then
    login
  fi
}

tools_list() {
  rpc_post "tools/list" "{}"
}

call_tool() {
  local tool_name="$1"
  local args_json="$2"
  ensure_token

  local token
  token="$(cat "${TOKEN_FILE}")"

  # Injeta session_token quando o caller não passou explicitamente.
  local final_args
  final_args="$(python3 - <<'PY' "${args_json}" "${token}"
import json,sys
args=json.loads(sys.argv[1])
token=sys.argv[2]
if "session_token" not in args:
    args["session_token"]=token
print(json.dumps(args, ensure_ascii=False))
PY
)"

  rpc_post "tools/call" "{\"name\":\"${tool_name}\",\"arguments\":${final_args}}"
}

cmd="${1:-}"
case "${cmd}" in
  login)
    login
    ;;
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
