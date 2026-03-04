#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
STATE_DIR="${PROJECT_ROOT}/workspace/.state"
TOKEN_FILE="${STATE_DIR}/smartenvios_mcp_session_token"
DEFAULT_MCP_URL="https://staging.smartenvios.tec.br/mcp"

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

MCP_URL="${SMARTENVIOS_MCP_URL:-$(read_env_var SMARTENVIOS_MCP_URL "${ENV_FILE}")}"
MCP_URL="${MCP_URL:-${DEFAULT_MCP_URL}}"
MCP_FALLBACK_URL="${SMARTENVIOS_MCP_FALLBACK_URL:-$(read_env_var SMARTENVIOS_MCP_FALLBACK_URL "${ENV_FILE}")}"
MCP_EMAIL="${SMARTENVIOS_MCP_EMAIL:-$(read_env_var SMARTENVIOS_MCP_EMAIL "${ENV_FILE}")}"
MCP_PASSWORD="${SMARTENVIOS_MCP_PASSWORD:-$(read_env_var SMARTENVIOS_MCP_PASSWORD "${ENV_FILE}")}"

if [[ -z "${MCP_FALLBACK_URL}" ]]; then
  case "${MCP_URL}" in
    http://localhost:*|https://localhost:*|http://127.0.0.1:*|https://127.0.0.1:*|http://[::1]:*|https://[::1]:*)
      if [[ "${MCP_URL}" != "${DEFAULT_MCP_URL}" ]]; then
        MCP_FALLBACK_URL="${DEFAULT_MCP_URL}"
      fi
      ;;
  esac
fi

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
  python3 - "$MCP_URL" "$MCP_FALLBACK_URL" "$method" "$params" <<'PY'
import json
import socket
import sys
import urllib.error
import urllib.request

primary_url = sys.argv[1]
fallback_url = sys.argv[2]
method = sys.argv[3]
params = json.loads(sys.argv[4])

payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
urls = []
for candidate in (primary_url, fallback_url):
    if candidate and candidate not in urls:
        urls.append(candidate)

last_http_error = None
attempt_errors = []

for index, url in enumerate(urls):
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=45) as resp:
            print(resp.read().decode())
            sys.exit(0)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        attempt_errors.append(f"{url} -> HTTP {exc.code}")
        last_http_error = (exc, body)
        should_retry = index == 0 and fallback_url and 500 <= exc.code < 600
        if should_retry:
            continue
        sys.stderr.write(f"Erro MCP em {url}: HTTP {exc.code}\n{body}\n")
        sys.exit(1)
    except (urllib.error.URLError, socket.timeout, TimeoutError) as exc:
        attempt_errors.append(f"{url} -> {exc}")
        should_retry = index == 0 and fallback_url
        if should_retry:
            continue
        sys.stderr.write(f"Erro MCP em {url}: {exc}\n")
        sys.exit(1)

if last_http_error is not None:
    exc, body = last_http_error
    sys.stderr.write(
        "Erro MCP em todos os endpoints configurados: "
        + " | ".join(attempt_errors)
        + "\n"
        + body
        + "\n"
    )
else:
    sys.stderr.write(
        "Erro MCP em todos os endpoints configurados: "
        + " | ".join(attempt_errors)
        + "\n"
    )
sys.exit(1)
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
