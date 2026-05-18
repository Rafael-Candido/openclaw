#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
STATE_DIR="${PROJECT_ROOT}/workspace/.state"
TOKEN_FILE="${STATE_DIR}/smartenvios_mcp_session_token"
EINSTEIN_JIRA_HELPER="${PROJECT_ROOT}/workspace/agents/einstein/scripts/jira-helper.sh"
DEFAULT_MCP_URL="https://staging.smartenvios.tec.br/mcp"
MCP_RPC_RETRIES="${MCP_RPC_RETRIES:-2}"
MCP_RPC_RETRY_DELAY_SEC="${MCP_RPC_RETRY_DELAY_SEC:-1}"

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

read_config_var() {
  local key="$1"
  local file="$2"
  local file_value env_value

  file_value="$(read_env_var "${key}" "${file}")"
  env_value="${!key:-}"

  # OpenClaw daemons can keep old environment variables after .env changes.
  # Prefer the project .env by default so credential rotation takes effect
  # without restarting the Discord/gateway process. Set
  # SMARTENVIOS_MCP_PREFER_ENV=true only for explicit one-off overrides.
  if [[ "${SMARTENVIOS_MCP_PREFER_ENV:-false}" == "true" && -n "${env_value}" ]]; then
    printf '%s' "${env_value}"
  elif [[ -n "${file_value}" ]]; then
    printf '%s' "${file_value}"
  else
    printf '%s' "${env_value}"
  fi
}

MCP_URL="$(read_config_var SMARTENVIOS_MCP_URL "${ENV_FILE}")"
MCP_URL="${MCP_URL:-${DEFAULT_MCP_URL}}"
MCP_FALLBACK_URL="$(read_config_var SMARTENVIOS_MCP_FALLBACK_URL "${ENV_FILE}")"
MCP_EMAIL="$(read_config_var SMARTENVIOS_MCP_EMAIL "${ENV_FILE}")"
MCP_PASSWORD="$(read_config_var SMARTENVIOS_MCP_PASSWORD "${ENV_FILE}")"

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
  $0 tools-names
  $0 has-tool <regex>
  $0 call <tool_name> '<json_args>'

Exemplos:
  $0 login
  $0 tools
  $0 tools-names
  $0 has-tool '^jira_'
  $0 call smartenvios_quote_freight '{"zip_code_start":"14020510","zip_code_end":"01305100","volumes":[{"quantity":1,"length":20,"height":10,"weight":1,"width":15}, "timeout": 5000}'  # Added timeout for CEP calls to improve performance
EOF
}

rpc_post() {
  local method="$1"
  local params="$2"
  python3 - "$MCP_URL" "$MCP_FALLBACK_URL" "$method" "$params" "${MCP_RPC_RETRIES}" "${MCP_RPC_RETRY_DELAY_SEC}" <<'PY'
import json
import socket
import time
import sys
import urllib.error
import urllib.request

primary_url = sys.argv[1]
fallback_url = sys.argv[2]
method = sys.argv[3]
params = json.loads(sys.argv[4])
max_attempts = max(1, int(sys.argv[5]))
retry_delay = max(0.0, float(sys.argv[6]))

payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
urls = []
for candidate in (primary_url, fallback_url):
    if candidate and candidate not in urls:
        urls.append(candidate)

last_http_error = None
attempt_errors = []

for index, url in enumerate(urls):
    for attempt in range(1, max_attempts + 1):
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
            attempt_errors.append(f"{url} -> HTTP {exc.code} (attempt {attempt}/{max_attempts})")
            last_http_error = (exc, body)
            retriable_http = exc.code == 429 or (500 <= exc.code < 600)
            if retriable_http and attempt < max_attempts:
                if retry_delay:
                    time.sleep(retry_delay)
                continue
            should_try_fallback = index == 0 and fallback_url and (retriable_http or exc.code in (401, 403))
            if should_try_fallback:
                break
            sys.stderr.write(f"Erro MCP em {url}: HTTP {exc.code}\n{body}\n")
            sys.exit(1)
        except (urllib.error.URLError, socket.timeout, TimeoutError) as exc:
            attempt_errors.append(f"{url} -> {exc} (attempt {attempt}/{max_attempts})")
            if attempt < max_attempts:
                if retry_delay:
                    time.sleep(retry_delay)
                continue
            should_try_fallback = index == 0 and fallback_url
            if should_try_fallback:
                break
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

json_has_session_token() {
  local args_json="$1"
  python3 - <<'PY' "${args_json}"
import json, sys
try:
    args = json.loads(sys.argv[1])
except Exception:
    print("0")
    raise SystemExit(0)
print("1" if "session_token" in args else "0")
PY
}

inject_session_token() {
  local args_json="$1"
  local token
  token="$(cat "${TOKEN_FILE}")"

  python3 - <<'PY' "${args_json}" "${token}"
import json,sys
args=json.loads(sys.argv[1])
token=sys.argv[2]
if "session_token" not in args:
    args["session_token"]=token
print(json.dumps(args, ensure_ascii=False))
PY
}

is_auth_error_text() {
  local text="${1:-}"
  python3 - <<'PY' "${text}"
import json
import re
import sys

text = sys.argv[1] if len(sys.argv) > 1 else ""
patterns = [
    r"http\s*401",
    r"http\s*403",
    r"unauthorized",
    r"forbidden",
    r"invalid\s+session",
    r"sess[aã]o\s+inv[aá]lida",
    r"sess[aã]o\s+expirada",
    r"session[_\s-]*token",
    r"token\s+(?:invalid|expired|missing)",
    r"not\s+authenticated",
    r"auth(?:entication)?\s+(?:failed|required|invalid)",
    r"fa[çc]a\s+login",
    r"auth_login",
]
if any(re.search(p, text, flags=re.I) for p in patterns):
    print("1")
    raise SystemExit(0)

try:
    obj = json.loads(text)
except Exception:
    print("0")
    raise SystemExit(0)

haystacks = []
err = obj.get("error")
if isinstance(err, dict):
    haystacks.append(str(err.get("message", "")))
    haystacks.append(str(err.get("data", "")))

for c in ((obj.get("result") or {}).get("content") or []):
    if isinstance(c, dict) and c.get("type") == "text":
        haystacks.append(str(c.get("text", "")))

joined = "\n".join(haystacks)
print("1" if any(re.search(p, joined, flags=re.I) for p in patterns) else "0")
PY
}

slugify_label() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import re
import sys
import unicodedata

text = sys.argv[1] if len(sys.argv) > 1 else ""
text = text.lower()
text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
print(text)
PY
}

normalize_priority_name() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import re
import sys
import unicodedata

value = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if not value:
    print("")
    raise SystemExit(0)

def norm(text: str) -> str:
    text = text.lower()
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
    text = re.sub(r"[^a-z0-9]+", " ", text).strip()
    return text

token = norm(value)
mapping = {
    "highest": "Highest",
    "urgent": "Highest",
    "urgente": "Highest",
    "critical": "Highest",
    "critica": "Highest",
    "critico": "Highest",
    "maxima": "Highest",
    "maximo": "Highest",
    "altissima": "Highest",
    "blocker": "Highest",
    "bloqueante": "Highest",
    "p0": "Highest",
    "high": "High",
    "alta": "High",
    "alto": "High",
    "p1": "High",
    "medium": "Medium",
    "media": "Medium",
    "medio": "Medium",
    "normal": "Medium",
    "p2": "Medium",
    "low": "Low",
    "baixa": "Low",
    "baixo": "Low",
    "p3": "Low",
    "lowest": "Lowest",
    "baixissima": "Lowest",
    "minima": "Lowest",
    "minimo": "Lowest",
    "p4": "Lowest",
}
if token in mapping:
    print(mapping[token])
    raise SystemExit(0)

for key in ("highest", "high", "medium", "low", "lowest"):
    if re.search(rf"(?:^|\s){key}(?:$|\s)", token):
        print(mapping[key])
        raise SystemExit(0)

print(value)
PY
}

extract_target_priority() {
  local args_json="$1"
  local candidate normalized
  candidate="$(python3 - <<'PY' "${args_json}"
import json
import re
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else "{}"
try:
    obj = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

def first_candidate(values):
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""

def ordinal_to_priority(index: int) -> str:
    if index <= 1:
        return "Highest"
    if index == 2:
        return "High"
    if index == 3:
        return "Medium"
    if index == 4:
        return "Low"
    return "Lowest"

def extract_ordinal(text: str):
    if not text:
        return None
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in lines[:6]:
        m = re.match(r"^(\d+)[\.\)]\s+", line)
        if m:
            return int(m.group(1))
    m = re.search(r"##\s*solicita[cç][aã]o[^\n]*\n\s*(\d+)[\.\)]\s+", text, flags=re.I)
    if m:
        return int(m.group(1))
    return None

candidates = []
fields = obj.get("fields")
if isinstance(fields, dict):
    p = fields.get("priority")
    if isinstance(p, dict):
        candidates.append(p.get("name"))
    elif isinstance(p, str):
        candidates.append(p)

p = obj.get("priority")
if isinstance(p, dict):
    candidates.append(p.get("name"))
elif isinstance(p, str):
    candidates.append(p)

candidate = first_candidate(candidates)
if not candidate:
    summary = obj.get("summary")
    description = obj.get("description")
    summary = summary if isinstance(summary, str) else ""
    description = description if isinstance(description, str) else ""
    idx = extract_ordinal(summary)
    if idx is None:
        idx = extract_ordinal(description)
    if idx is not None:
        candidate = ordinal_to_priority(idx)

print(candidate)
PY
)"
  normalized="$(normalize_priority_name "${candidate}")"
  [[ -n "${normalized}" ]] || normalized="Highest"
  printf '%s\n' "${normalized}"
}

is_non_applicable_value() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import re
import sys
import unicodedata

value = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if not value:
    print("1")
    raise SystemExit(0)

value = value.lower()
value = "".join(c for c in unicodedata.normalize("NFD", value) if not unicodedata.combining(c))
value = re.sub(r"[^a-z0-9]+", " ", value).strip()

placeholders = {
    "nao se aplica",
    "na",
    "n a",
    "none",
    "null",
    "sem classificacao",
    "not applicable",
    "nenhum",
    "nenhuma",
    "sem categoria",
    "sem produto",
    "sem projeto",
}
print("1" if value in placeholders else "0")
PY
}

extract_issue_key_from_rpc() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import json
import re
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
key = ""

try:
    obj = json.loads(raw)
    for c in ((obj.get("result") or {}).get("content") or []):
        if not isinstance(c, dict) or c.get("type") != "text":
            continue
        txt = str(c.get("text", ""))
        try:
            inner = json.loads(txt)
            key = str(inner.get("key") or "")
            if key:
                break
        except Exception:
            m = re.search(r"\b[A-Z][A-Z0-9]+-\d+\b", txt)
            if m:
                key = m.group(0)
                break
except Exception:
    m = re.search(r"\b[A-Z][A-Z0-9]+-\d+\b", raw)
    if m:
        key = m.group(0)

print(key)
PY
}

sanitize_jira_create_output() {
  local args_json="$1"
  local raw_out="$2"
  python3 - <<'PY' "${raw_out}" "${args_json}"
import json
import re
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
args_raw = sys.argv[2] if len(sys.argv) > 2 else "{}"

def jload(text):
    try:
        return json.loads(text)
    except Exception:
        return None

def pick_text(value):
    if isinstance(value, str):
        return value.strip()
    return ""

def pick_name(value):
    if isinstance(value, dict):
        for key in ("displayName", "name", "value"):
            text = pick_text(value.get(key))
            if text:
                return text
    return pick_text(value)

def normalize_priority(value):
    token = re.sub(r"[^a-z0-9]+", "", (value or "").lower())
    mapping = {
        "highest": "Highest",
        "high": "High",
        "medium": "Medium",
        "low": "Low",
        "lowest": "Lowest",
        "urgent": "Highest",
        "critical": "Highest",
        "p0": "Highest",
        "p1": "High",
        "p2": "Medium",
        "p3": "Low",
        "p4": "Lowest",
    }
    return mapping.get(token, value.strip() if isinstance(value, str) else "")

args = jload(args_raw) or {}
info = {
    "key": "",
    "assignee": pick_text(args.get("assignee_name")),
    "issue_type": pick_text(args.get("issue_type")),
    "priority": "",
    "link": "",
}

fields = args.get("fields") if isinstance(args.get("fields"), dict) else {}
if not info["issue_type"]:
    info["issue_type"] = pick_name(fields.get("issuetype")) or "Task"

priority_arg = args.get("priority")
if isinstance(priority_arg, dict):
    info["priority"] = normalize_priority(pick_name(priority_arg))
elif isinstance(priority_arg, str):
    info["priority"] = normalize_priority(priority_arg)
if not info["priority"]:
    info["priority"] = normalize_priority(pick_name(fields.get("priority")))

def consume_dict(data):
    if not isinstance(data, dict):
        return

    fields_obj = data.get("fields") if isinstance(data.get("fields"), dict) else {}

    if not info["key"]:
        info["key"] = pick_text(data.get("key"))
    if not info["assignee"]:
        info["assignee"] = pick_name(data.get("assignee")) or pick_name(fields_obj.get("assignee"))
    if not info["issue_type"]:
        info["issue_type"] = (
            pick_name(data.get("issue_type"))
            or pick_name(data.get("issueType"))
            or pick_name(fields_obj.get("issuetype"))
        )
    if not info["priority"]:
        info["priority"] = normalize_priority(
            pick_name(data.get("priority")) or pick_name(fields_obj.get("priority"))
        )
    if not info["link"]:
        for candidate in (data.get("link"), data.get("url"), data.get("browseUrl"), data.get("self")):
            text = pick_text(candidate)
            if text:
                info["link"] = text
                break

rpc = jload(raw)
if not isinstance(rpc, dict):
    print(raw)
    raise SystemExit(0)

consume_dict(rpc)
result_obj = rpc.get("result") if isinstance(rpc.get("result"), dict) else {}
consume_dict(result_obj)

for content in result_obj.get("content") or []:
    if not isinstance(content, dict) or content.get("type") != "text":
        continue
    text = str(content.get("text", ""))

    parsed = jload(text)
    if isinstance(parsed, dict):
        consume_dict(parsed)
    elif isinstance(parsed, list):
        for item in parsed:
            if isinstance(item, dict):
                consume_dict(item)

    if not info["key"]:
        match = re.search(r"\b[A-Z][A-Z0-9]+-\d+\b", text)
        if match:
            info["key"] = match.group(0)

if not info["key"]:
    match = re.search(r"\b[A-Z][A-Z0-9]+-\d+\b", raw)
    if match:
        info["key"] = match.group(0)

if not info["key"]:
    print(raw)
    raise SystemExit(0)

if not info["issue_type"]:
    info["issue_type"] = "Task"
if not info["priority"]:
    info["priority"] = "Highest"

if info["link"]:
    if "/browse/" not in info["link"]:
        base_match = re.match(r"^(https?://[^/]+)", info["link"])
        if base_match:
            info["link"] = f"{base_match.group(1)}/browse/{info['key']}"
elif info["key"]:
    info["link"] = f"https://smartenv.atlassian.net/browse/{info['key']}"

compact = {
    "status": "created",
    "key": info["key"],
    "assignee": info["assignee"],
    "issue_type": info["issue_type"],
    "priority": info["priority"],
    "link": info["link"],
}
sanitized = {
    "jsonrpc": rpc.get("jsonrpc", "2.0"),
    "id": rpc.get("id", 1),
    "result": {"content": [{"type": "text", "text": json.dumps(compact, ensure_ascii=False)}]},
}
print(json.dumps(sanitized, ensure_ascii=False))
PY
}

extract_assignee_account_id_from_rpc() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import json
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
account_id = ""

try:
    obj = json.loads(raw)
    for c in ((obj.get("result") or {}).get("content") or []):
        if not isinstance(c, dict) or c.get("type") != "text":
            continue
        txt = str(c.get("text", ""))
        try:
            inner = json.loads(txt)
        except Exception:
            continue
        if isinstance(inner, dict):
            assignee = inner.get("assignee")
            if isinstance(assignee, dict):
                account_id = str(assignee.get("accountId") or "")
                if account_id:
                    break
except Exception:
    pass

print(account_id)
PY
}

extract_account_id_from_search_rpc() {
  local raw="${1:-}"
  local target_name="${2:-}"
  python3 - <<'PY' "${raw}" "${target_name}"
import json
import re
import sys
import unicodedata

raw = sys.argv[1] if len(sys.argv) > 1 else ""
target = sys.argv[2] if len(sys.argv) > 2 else ""

def norm(text: str) -> str:
    text = text.lower()
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
    text = re.sub(r"\s+", " ", text).strip()
    return text

target_n = norm(target)
target_tokens = [t for t in target_n.split(" ") if t]
best_score = -1
best_id = ""

try:
    obj = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

users = []
for c in ((obj.get("result") or {}).get("content") or []):
    if not isinstance(c, dict) or c.get("type") != "text":
        continue
    txt = str(c.get("text", ""))
    try:
        parsed = json.loads(txt)
    except Exception:
        continue
    if isinstance(parsed, list):
        users.extend(parsed)
    elif isinstance(parsed, dict):
        users.append(parsed)

for user in users:
    if not isinstance(user, dict):
        continue
    account_id = str(user.get("accountId") or "")
    if not account_id:
        continue
    display = str(user.get("displayName") or "")
    display_n = norm(display)
    score = 0
    if user.get("active") is True:
        score += 5
    if target_n and display_n == target_n:
        score += 100
    elif target_n and display_n.startswith(target_n):
        score += 80
    elif target_n and target_n in display_n:
        score += 60
    if target_tokens and all(token in display_n for token in target_tokens):
        score += 40
    if target_tokens:
        score += sum(5 for token in target_tokens if token in display_n)
    if score > best_score:
        best_score = score
        best_id = account_id

print(best_id if best_score > 0 else "")
PY
}

extract_issue_status_name_from_rpc() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import json
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
status_name = ""

try:
    obj = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

for c in ((obj.get("result") or {}).get("content") or []):
    if not isinstance(c, dict) or c.get("type") != "text":
        continue
    txt = str(c.get("text", ""))
    try:
        parsed = json.loads(txt)
    except Exception:
        continue
    if isinstance(parsed, dict):
        status_name = str((((parsed.get("fields") or {}).get("status") or {}).get("name")) or "")
        if status_name:
            break

print(status_name)
PY
}

pick_todo_transition_name_from_list_rpc() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import json
import re
import sys
import unicodedata

raw = sys.argv[1] if len(sys.argv) > 1 else ""

def norm(text: str) -> str:
    text = text.lower()
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
    text = re.sub(r"[^a-z0-9]+", " ", text).strip()
    return text

def score_transition(t: dict) -> int:
    name = str(t.get("name") or "")
    to_name = str((t.get("to") or {}).get("name") or "")
    name_n = norm(name)
    to_n = norm(to_name)
    status_cat = str(((t.get("to") or {}).get("statusCategory") or {}).get("key") or "")

    if "backlog" in name_n or "backlog" in to_n:
        return -10

    preferred = {"to do", "tarefas pendentes", "pendente", "pending"}
    if to_n in preferred:
        return 120
    if name_n in preferred:
        return 110
    if "to do" in to_n or "tarefas pendentes" in to_n:
        return 100
    if "to do" in name_n or "tarefas pendentes" in name_n:
        return 95
    if status_cat == "new" and to_n and "backlog" not in to_n:
        return 60
    return 0

best_name = ""
best_score = 0

try:
    obj = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

transitions = []
for c in ((obj.get("result") or {}).get("content") or []):
    if not isinstance(c, dict) or c.get("type") != "text":
        continue
    txt = str(c.get("text", ""))
    try:
        parsed = json.loads(txt)
    except Exception:
        continue
    if isinstance(parsed, dict):
        arr = parsed.get("transitions") or []
        if isinstance(arr, list):
            transitions.extend(arr)

for t in transitions:
    if not isinstance(t, dict):
        continue
    s = score_transition(t)
    if s > best_score:
        best_score = s
        best_name = str(t.get("name") or "")

print(best_name if best_score >= 90 else "")
PY
}

normalize_multiline_text() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import re
import sys

text = sys.argv[1] if len(sys.argv) > 1 else ""
if not text:
    print("")
    raise SystemExit(0)

text = text.replace("\r\n", "\n").replace("\r", "\n")
# Alguns payloads chegam com \n literal; converte para quebra real.
text = text.replace("\\n", "\n").replace("\\t", " ")
text = text.replace("\u200b", "")
text = "\n".join(line.rstrip() for line in text.split("\n"))
text = re.sub(r"\n{3,}", "\n\n", text).strip()
print(text)
PY
}

normalize_jira_template_layout() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import re
import sys

text = sys.argv[1] if len(sys.argv) > 1 else ""
if not text:
    print("")
    raise SystemExit(0)

text = text.replace("\r\n", "\n").replace("\r", "\n")
text = text.replace("\\n", "\n").replace("\\t", " ")
text = text.replace("\u200b", "")

# Garante quebra de linha antes de cada heading da template Jira.
for heading in [
    r"##\s*Solicita[cç][aã]o do usu[aá]rio:?",
    r"##\s*Objetivo:?",
    r"##\s*Crit[eé]rios de aceite:?",
]:
    text = re.sub(rf"\s*({heading})", r"\n\n\1", text, flags=re.I)

# Garante conteúdo em linha separada após o heading.
text = re.sub(
    r"(##\s*Solicita[cç][aã]o do usu[aá]rio:?)\s*(?!\n)",
    r"\1\n",
    text,
    flags=re.I,
)
text = re.sub(r"(##\s*Objetivo:?)\s*(?!\n)", r"\1\n", text, flags=re.I)
text = re.sub(
    r"(##\s*Crit[eé]rios de aceite:?)\s*(?!\n)",
    r"\1\n",
    text,
    flags=re.I,
)

text = "\n".join(line.rstrip() for line in text.split("\n"))
text = re.sub(r"\n{3,}", "\n\n", text).strip()
print(text)
PY
}

build_jira_adf_description() {
  local raw="${1:-}"
  python3 - <<'PY' "${raw}"
import json
import re
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
text = raw.replace("\r\n", "\n").replace("\r", "\n").replace("\\n", "\n")
lines = text.split("\n")

nodes = []
bullet_items = []
ordered_items = []

def paragraph(text_value: str):
    text_value = text_value.strip()
    if not text_value:
        return None
    if re.fullmatch(r"https?://\S+", text_value):
        return {
            "type": "paragraph",
            "content": [
                {
                    "type": "text",
                    "text": text_value,
                    "marks": [{"type": "link", "attrs": {"href": text_value}}],
                }
            ],
        }
    return {"type": "paragraph", "content": [{"type": "text", "text": text_value}]}

def flush_bullets():
    global bullet_items
    if not bullet_items:
        return
    nodes.append(
        {
            "type": "bulletList",
            "content": [
                {
                    "type": "listItem",
                    "content": [
                        {
                            "type": "paragraph",
                            "content": [{"type": "text", "text": item}],
                        }
                    ],
                }
                for item in bullet_items
            ],
        }
    )
    bullet_items = []

def flush_ordered():
    global ordered_items
    if not ordered_items:
        return
    nodes.append(
        {
            "type": "orderedList",
            "attrs": {"order": 1},
            "content": [
                {
                    "type": "listItem",
                    "content": [
                        {
                            "type": "paragraph",
                            "content": [{"type": "text", "text": item}],
                        }
                    ],
                }
                for item in ordered_items
            ],
        }
    )
    ordered_items = []

for line in lines:
    line = line.rstrip()
    if not line.strip():
        flush_bullets()
        flush_ordered()
        continue
    heading_match = re.match(r"^\s*(#{1,6})\s+(.+?)\s*$", line)
    if heading_match:
        flush_bullets()
        flush_ordered()
        heading_level = len(heading_match.group(1))
        nodes.append(
            {
                "type": "heading",
                "attrs": {"level": heading_level},
                "content": [{"type": "text", "text": heading_match.group(2).strip()}],
            }
        )
        continue

    bullet_match = re.match(r"^\s*[-*]\s+(.+?)\s*$", line)
    if bullet_match:
        flush_ordered()
        bullet_items.append(bullet_match.group(1).strip())
        continue

    ordered_match = re.match(r"^\s*\d+\.\s+(.+?)\s*$", line)
    if ordered_match:
        flush_bullets()
        ordered_items.append(ordered_match.group(1).strip())
        continue

    flush_bullets()
    flush_ordered()
    node = paragraph(line)
    if node:
        nodes.append(node)

flush_bullets()
flush_ordered()

if not nodes:
    nodes = [{"type": "paragraph"}]

print(json.dumps({"type": "doc", "version": 1, "content": nodes}, ensure_ascii=False))
PY
}

build_jira_objective_and_criteria() {
  local summary="${1:-}"
  local solicitation="${2:-}"
  local reason="${3:-tarefa}"
  python3 - <<'PY' "${summary}" "${solicitation}" "${reason}"
import json
import re
import sys

summary = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
solicitation = (sys.argv[2] if len(sys.argv) > 2 else "").strip()
reason = (sys.argv[3] if len(sys.argv) > 3 else "tarefa").strip().lower()
context = f"{summary}\n{solicitation}".strip()

analysis_re = re.compile(
    r"(an[aá]lise|ader[eê]ncia|proposta|reprecifica|competitiv|tabela|renegocia|cota[cç][aã]o|pricing|faixa|origem)",
    re.I,
)

def normalize_item(text: str, max_len: int = 220) -> str:
    text = re.sub(r"\s+", " ", (text or "")).strip(" .-\t")
    if not text:
        return ""
    if len(text) > max_len:
        text = text[: max_len - 3].rstrip() + "..."
    return text

def extract_scope_items(text: str):
    if not text:
        return []
    items = []
    for raw in text.splitlines():
        line = (raw or "").strip()
        if not line:
            continue
        if re.match(r"^solicitante\s*:", line, flags=re.I):
            continue
        if re.match(r"^(backend|frontend)\s*:", line, flags=re.I):
            role, content = re.split(r":", line, maxsplit=1)
            content = normalize_item(content)
            if content:
                items.append(f"{role.strip().capitalize()}: {content}")
            continue
        if re.match(r"^[-*•]\s+", line) or re.match(r"^\d+[\).\-\s]+", line):
            line = re.sub(r"^[-*•]\s+|^\d+[\).\-\s]+", "", line).strip()
            line = normalize_item(line)
            if line:
                items.append(line)
            continue
        if ";" in line and len(line) > 40:
            for part in re.split(r";+", line):
                part = normalize_item(part)
                if part:
                    items.append(part)
            continue
        if len(line) > 25:
            line = normalize_item(line)
            if line:
                items.append(line)

    dedup = []
    seen = set()
    for item in items:
        key = re.sub(r"[^a-z0-9]+", "", item.lower())
        if not key or key in seen:
            continue
        seen.add(key)
        dedup.append(item.rstrip("."))
    return dedup[:5]

def clean_scope(text: str) -> str:
    if not text:
        return ""
    text = re.sub(r"https?://\S+", "", text, flags=re.I)
    lines = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if re.match(r"^solicitante\s*:", line, flags=re.I):
            continue
        line = line.strip('"').strip("'")
        lines.append(line)
    scope = " ".join(lines)
    scope = re.sub(r"\s+", " ", scope).strip(" .-")
    if len(scope) > 220:
        scope = scope[:217].rstrip() + "..."
    return scope

scope_hint = clean_scope(summary) or clean_scope(solicitation)
is_analysis = bool(analysis_re.search(context))
scope_items = extract_scope_items(solicitation or summary)

if reason == "bug":
    base_objective = "Corrigir a falha reportada garantindo estabilidade do fluxo impactado."
elif is_analysis:
    base_objective = "Concluir a análise solicitada com parecer objetivo para tomada de decisão."
elif reason == "melhoria":
    base_objective = "Implementar a evolução solicitada no fluxo de negócio descrito."
else:
    base_objective = "Executar a demanda solicitada com resultado verificável e sem regressão."

objective_lines = [base_objective]
if scope_items:
    objective_lines.append("Escopo objetivo:")
    for item in scope_items[:4]:
        objective_lines.append(f"- {item}")
elif scope_hint:
    objective_lines.append(f"Foco principal: {scope_hint}.")

criteria = []
if scope_items:
    for item in scope_items[:3]:
        criteria.append(f"- Cenário validado: {item}.")
else:
    criteria.append("- Escopo solicitado implementado e validado em cenário funcional.")

if re.search(r"\b(back|front)end\b", context, flags=re.I):
    criteria.append("- Entregas de backend e frontend integradas e validadas no mesmo fluxo.")
if re.search(r"pr[eé]-?pago|saldo|inadimpl", context, flags=re.I):
    criteria.append("- Regra financeira validada: sem saldo, primeira guia paga e integração desativada até recomposição.")
if re.search(r"100%\s*smart|outros canais|duplicad", context, flags=re.I):
    criteria.append("- Elegibilidade da integração validada para evitar cobrança duplicada em clientes não 100% SmartEnvios.")

criteria.append("- Evidências de validação funcional registradas na issue.")
criteria.append("- Fluxos impactados validados sem regressão.")

dedup_criteria = []
seen_criteria = set()
for item in criteria:
    key = re.sub(r"[^a-z0-9]+", "", item.lower())
    if key in seen_criteria:
        continue
    seen_criteria.add(key)
    dedup_criteria.append(item)
criteria = dedup_criteria

objective = "\n".join(objective_lines)

print(json.dumps({"objective": objective, "criteria": "\n".join(criteria)}, ensure_ascii=False))
PY
}

extract_jira_solicitation_section() {
  local raw_description="${1:-}"
  python3 - <<'PY' "${raw_description}"
import re
import sys

text = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if not text:
    print("")
    raise SystemExit(0)

match = re.search(
    r"##\s*Solicita[cç][aã]o do usu[aá]rio:?\s*(.*?)(?:\n##\s*Objetivo\b|\Z)",
    text,
    flags=re.I | re.S,
)
if not match:
    print("")
    raise SystemExit(0)

print(match.group(1).strip())
PY
}

has_jira_section_heading() {
  local raw_description="${1:-}"
  local section="${2:-}"
  python3 - <<'PY' "${raw_description}" "${section}"
import re
import sys

text = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
section = (sys.argv[2] if len(sys.argv) > 2 else "").strip().lower()
if not text or not section:
    print("0")
    raise SystemExit(0)

patterns = {
    "solicitacao": r"##\s*Solicita[cç][aã]o do usu[aá]rio:?",
    "objetivo": r"##\s*Objetivo:?",
    "criterios": r"##\s*Crit[eé]rios de aceite:?",
}
pattern = patterns.get(section)
if not pattern:
    print("0")
    raise SystemExit(0)

print("1" if re.search(pattern, text, flags=re.I) else "0")
PY
}

jira_template_is_generic() {
  local raw_description="${1:-}"
  python3 - <<'PY' "${raw_description}"
import re
import sys

text = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if not text:
    print("1")
    raise SystemExit(0)

has_template = (
    re.search(r"##\s*Solicita[cç][aã]o do usu[aá]rio", text, flags=re.I)
    and re.search(r"##\s*Objetivo", text, flags=re.I)
    and re.search(r"##\s*Crit[eé]rios de aceite", text, flags=re.I)
)
if not has_template:
    print("0")
    raise SystemExit(0)

objective_match = re.search(
    r"##\s*Objetivo:?\s*(.*?)(?:\n##\s*Crit[eé]rios de aceite\b|\Z)",
    text,
    flags=re.I | re.S,
)
criteria_match = re.search(
    r"##\s*Crit[eé]rios de aceite:?\s*(.*)$",
    text,
    flags=re.I | re.S,
)
solicitation_match = re.search(
    r"##\s*Solicita[cç][aã]o do usu[aá]rio:?\s*(.*?)(?:\n##\s*Objetivo\b|\Z)",
    text,
    flags=re.I | re.S,
)

objective = (objective_match.group(1).strip() if objective_match else "")
criteria = (criteria_match.group(1).strip() if criteria_match else "")
solicitation = (solicitation_match.group(1).strip() if solicitation_match else "")

normalized_objective = re.sub(r"[^a-z0-9]+", "", objective.lower())
normalized_solicitation = re.sub(r"[^a-z0-9]+", "", solicitation.lower())
same_as_request = (
    bool(normalized_objective)
    and bool(normalized_solicitation)
    and (
        normalized_objective == normalized_solicitation
        or normalized_objective in normalized_solicitation
    )
)

generic_patterns = [
    r"implementar a melhoria solicitada com entrega funcional e valida[cç][aã]o do fluxo impactado",
    r"executar a demanda solicitada com escopo claro",
    r"escopo funcional implementado conforme solicita[cç][aã]o",
    r"evid[eê]ncias de valida[cç][aã]o funcional registradas na issue",
    r"fluxos impactados validados sem regress[aã]o",
    r"escopo executado conforme solicita[cç][aã]o do usu[aá]rio",
]

generic_hits = sum(1 for pattern in generic_patterns if re.search(pattern, text, flags=re.I))
criteria_bullets = len([line for line in criteria.splitlines() if line.strip().startswith("-")])
objective_chars = len(objective)

is_generic = (
    same_as_request
    or generic_hits >= 2
    or (generic_hits >= 1 and objective_chars < 140)
    or criteria_bullets < 2
)

print("1" if is_generic else "0")
PY
}

normalize_jira_create_args() {
  local args_json="$1"
  local summary description issue_type assignee_name reason target_priority
  local classification="{}"
  local class_product="" class_project="" class_integration="" class_category="" class_component=""
  local solicitation objective criteria desc_template desc_adf objective_meta
  local template_has_sections template_solicitation template_needs_rebuild

  summary="$(jq -r '.summary // empty' <<<"${args_json}" 2>/dev/null || true)"
  if [[ -z "${summary}" ]]; then
    printf '%s\n' "${args_json}"
    return 0
  fi

  description="$(jq -r 'if (.description|type)=="string" then .description else "" end' <<<"${args_json}" 2>/dev/null || true)"
  summary="$(normalize_multiline_text "${summary}")"
  description="$(normalize_multiline_text "${description}")"
  description="$(normalize_jira_template_layout "${description}")"
  issue_type="$(jq -r '.issue_type // ""' <<<"${args_json}" 2>/dev/null || true)"
  assignee_name="$(jq -r '.assignee_name // ""' <<<"${args_json}" 2>/dev/null || true)"

  case "$(printf '%s' "${issue_type}" | tr '[:upper:]' '[:lower:]')" in
    bug) reason="bug" ;;
    story) reason="melhoria" ;;
    *) reason="tarefa" ;;
  esac

  if [[ -x "${EINSTEIN_JIRA_HELPER}" ]]; then
    if [[ -n "${assignee_name}" ]]; then
      classification="$("${EINSTEIN_JIRA_HELPER}" classify \
        --summary "${summary}" \
        --description "${description}" \
        --reason "${reason}" \
        --assignee "${assignee_name}" 2>/dev/null || echo '{}')"
    else
      classification="$("${EINSTEIN_JIRA_HELPER}" classify \
        --summary "${summary}" \
        --description "${description}" \
        --reason "${reason}" 2>/dev/null || echo '{}')"
    fi
  fi

  class_product="$(jq -r '.classification.product // empty' <<<"${classification}" 2>/dev/null || true)"
  class_project="$(jq -r '.classification.projectLabel // empty' <<<"${classification}" 2>/dev/null || true)"
  class_integration="$(jq -r '.classification.integration // empty' <<<"${classification}" 2>/dev/null || true)"
  class_category="$(jq -r '.classification.category // empty' <<<"${classification}" 2>/dev/null || true)"
  class_component="$(jq -r '.classification.component // empty' <<<"${classification}" 2>/dev/null || true)"
  target_priority="$(extract_target_priority "${args_json}")"

  if [[ "$(is_non_applicable_value "${class_product}")" == "1" ]]; then class_product=""; fi
  if [[ "$(is_non_applicable_value "${class_project}")" == "1" ]]; then class_project=""; fi
  if [[ "$(is_non_applicable_value "${class_integration}")" == "1" ]]; then class_integration=""; fi
  if [[ "$(is_non_applicable_value "${class_category}")" == "1" ]]; then class_category=""; fi
  if [[ "$(is_non_applicable_value "${class_component}")" == "1" ]]; then class_component=""; fi

  local has_solicitacao has_objetivo has_criterios template_has_core_sections
  template_has_sections=0
  template_has_core_sections=0
  has_solicitacao="$(has_jira_section_heading "${description}" "solicitacao")"
  has_objetivo="$(has_jira_section_heading "${description}" "objetivo")"
  has_criterios="$(has_jira_section_heading "${description}" "criterios")"
  if [[ "${has_solicitacao}" == "1" && "${has_objetivo}" == "1" ]]; then
    template_has_core_sections=1
  fi
  if [[ "${template_has_core_sections}" == "1" && "${has_criterios}" == "1" ]]; then
    template_has_sections=1
  fi

  solicitation="${description}"
  if [[ "${has_solicitacao}" == "1" ]]; then
    template_solicitation="$(extract_jira_solicitation_section "${description}")"
    if [[ -n "${template_solicitation}" ]]; then
      solicitation="${template_solicitation}"
    fi
  fi
  [[ -z "${solicitation}" ]] && solicitation="${summary}"
  objective_meta="$(build_jira_objective_and_criteria "${summary}" "${solicitation}" "${reason}")"
  objective="$(jq -r '.objective // "Executar a demanda solicitada com resultado verificável e sem regressão."' <<<"${objective_meta}" 2>/dev/null || true)"
  criteria="$(jq -r '.criteria // "- Escopo executado conforme solicitação.\n- Resultado e evidências registrados na issue.\n- Fluxo validado sem regressão no comportamento atual."' <<<"${objective_meta}" 2>/dev/null || true)"

  template_needs_rebuild=1
  if [[ "${template_has_sections}" == "1" ]]; then
    template_needs_rebuild="$(jira_template_is_generic "${description}")"
  elif [[ "${template_has_core_sections}" == "1" ]]; then
    # Se já veio estruturado do usuário (mesmo sem critérios), preserva para evitar duplicação.
    template_needs_rebuild=0
  fi

  if [[ "${template_has_core_sections}" == "1" && "${template_needs_rebuild}" == "0" ]]; then
    desc_template="${description}"
  else
    desc_template="## Solicitação do usuário:
${solicitation}

## Objetivo
${objective}

## Critérios de aceite
${criteria}"
  fi
  desc_template="$(normalize_jira_template_layout "${desc_template}")"
  desc_adf="$(build_jira_adf_description "${desc_template}")"

  jq -c \
    --argjson desc "${desc_adf}" \
    --arg p "${class_product}" \
    --arg pl "${class_project}" \
    --arg i "${class_integration}" \
    --arg c "${class_category}" \
    --arg priority "${target_priority}" \
    --arg comp "${class_component}" \
    '
      .issue_type = (if (.issue_type // "") == "" then "Task" else .issue_type end)
      | .description = $desc
      | .fields = (.fields // {})
      | .fields.priority = {name: $priority}
      | if (.product // "") == "" and $p != "" then .product = $p else . end
      | if (.project_label // "") == "" and $pl != "" then .project_label = $pl else . end
      | if (.integration // "") == "" and $i != "" then .integration = $i else . end
      | if (.category // "") == "" and $c != "" then .category = $c else . end
      | if (.component // "") == "" and $comp != "" then .component = $comp else . end
      | if (.fields | type) == "object" then
          .fields |= with_entries(select(.key != "customfield_10074" and .key != "customfield_10075" and .key != "customfield_10082"))
        else
          .
        end
    ' <<<"${args_json}"
}

normalize_jira_update_args() {
  local args_json="$1"
  local top_description fields_description top_adf fields_adf normalized

  top_description="$(jq -r 'if (.description|type)=="string" then .description else "" end' <<<"${args_json}" 2>/dev/null || true)"
  fields_description="$(jq -r 'if (.fields|type)=="object" and (.fields.description|type)=="string" then .fields.description else "" end' <<<"${args_json}" 2>/dev/null || true)"

  if [[ -z "${top_description}" && -z "${fields_description}" ]]; then
    printf '%s\n' "${args_json}"
    return 0
  fi

  normalized="${args_json}"
  if [[ -n "${top_description}" ]]; then
    top_description="$(normalize_multiline_text "${top_description}")"
    top_description="$(normalize_jira_template_layout "${top_description}")"
    top_adf="$(build_jira_adf_description "${top_description}")"
    normalized="$(jq -c --argjson desc "${top_adf}" '.description = $desc' <<<"${normalized}")"
  fi

  if [[ -n "${fields_description}" ]]; then
    fields_description="$(normalize_multiline_text "${fields_description}")"
    fields_description="$(normalize_jira_template_layout "${fields_description}")"
    fields_adf="$(build_jira_adf_description "${fields_description}")"
    normalized="$(jq -c --argjson desc "${fields_adf}" '.fields = (.fields // {}) | .fields.description = $desc' <<<"${normalized}")"
  fi

  printf '%s\n' "${normalized}"
}

postprocess_jira_create() {
  local args_json="$1"
  local create_out="$2"
  local issue_key target_priority category_label category_slug update_payload learn_context
  local assignee_name assignee_account_id create_assignee_account_id search_payload search_out assign_payload
  local get_issue_payload get_issue_out current_status_n transitions_payload transitions_out transition_name transition_payload

  issue_key="$(extract_issue_key_from_rpc "${create_out}")"
  [[ -n "${issue_key}" ]] || return 0

  target_priority="$(extract_target_priority "${args_json}")"
  [[ -z "${target_priority}" ]] && target_priority="Highest"
  category_label="$(jq -r '.category // empty' <<<"${args_json}" 2>/dev/null || true)"
  if [[ "$(is_non_applicable_value "${category_label}")" == "1" ]]; then
    category_label=""
  fi

  if [[ -n "${category_label}" ]]; then
    category_slug="$(slugify_label "${category_label}")"
  else
    category_slug=""
  fi

  if [[ -n "${category_slug}" ]]; then
    update_payload="$(jq -nc \
      --arg key "${issue_key}" \
      --arg priority "${target_priority}" \
      --arg label "categoria:${category_slug}" \
      '{issue_key: $key, fields: {priority: {name: $priority}}, update: {labels: [{add: $label}]}}')"
  else
    update_payload="$(jq -nc \
      --arg key "${issue_key}" \
      --arg priority "${target_priority}" \
      '{issue_key: $key, fields: {priority: {name: $priority}}}')"
  fi

  call_tool_once "jira_update_issue" "${update_payload}" >/dev/null 2>&1 || true

  assignee_name="$(jq -r '.assignee_name // empty' <<<"${args_json}" 2>/dev/null || true)"
  assignee_account_id="$(jq -r '.account_id // .assignee_account_id // .assignee.accountId // empty' <<<"${args_json}" 2>/dev/null || true)"
  create_assignee_account_id="$(extract_assignee_account_id_from_rpc "${create_out}")"

  if [[ -z "${assignee_account_id}" && -n "${create_assignee_account_id}" ]]; then
    assignee_account_id="${create_assignee_account_id}"
  fi

  if [[ -z "${assignee_account_id}" && -n "${assignee_name}" ]]; then
    search_payload="$(jq -nc --arg q "${assignee_name}" '{query: $q, maxResults: 15}')"
    search_out="$(call_tool_once "jira_search_users" "${search_payload}" 2>/dev/null || true)"
    assignee_account_id="$(extract_account_id_from_search_rpc "${search_out}" "${assignee_name}")"
  fi

  if [[ -n "${assignee_account_id}" ]]; then
    assign_payload="$(jq -nc --arg key "${issue_key}" --arg aid "${assignee_account_id}" '{issue_key: $key, account_id: $aid}')"
    call_tool_once "jira_assign_issue" "${assign_payload}" >/dev/null 2>&1 || true
  fi

  # Garante status em To do / Tarefas pendentes após criação.
  get_issue_payload="$(jq -nc --arg key "${issue_key}" '{issue_key: $key}')"
  get_issue_out="$(call_tool_once "jira_get_issue" "${get_issue_payload}" 2>/dev/null || true)"
  current_status_n="$(normalize_priority_name "$(extract_issue_status_name_from_rpc "${get_issue_out}")" | tr '[:upper:]' '[:lower:]')"

  if [[ "${current_status_n}" != "tarefas pendentes" && "${current_status_n}" != "to do" && "${current_status_n}" != "pending" && "${current_status_n}" != "pendente" ]]; then
    transitions_payload="$(jq -nc --arg key "${issue_key}" '{issue_key: $key}')"
    transitions_out="$(call_tool_once "jira_list_transitions" "${transitions_payload}" 2>/dev/null || true)"
    transition_name="$(pick_todo_transition_name_from_list_rpc "${transitions_out}")"
    if [[ -n "${transition_name}" ]]; then
      transition_payload="$(jq -nc --arg key "${issue_key}" --arg tn "${transition_name}" '{issue_key: $key, transition_name: $tn}')"
      call_tool_once "jira_transition_issue" "${transition_payload}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -x "${EINSTEIN_JIRA_HELPER}" ]]; then
    learn_context="$(jq -r '.summary // ""' <<<"${args_json}")"$'\n'"$(jq -r 'if (.description|type)=="string" then .description else "" end' <<<"${args_json}")"
    "${EINSTEIN_JIRA_HELPER}" learn-from-issue --issue-key "${issue_key}" --context "${learn_context}" >/dev/null 2>&1 || true
  fi
}

call_tool_once() {
  local tool_name="$1"
  local args_json="$2"
  ensure_token
  local final_args
  final_args="$(inject_session_token "${args_json}")"

  rpc_post "tools/call" "{\"name\":\"${tool_name}\",\"arguments\":${final_args}}"
}

emit_tool_output() {
  local tool_name="$1"
  local args_json="$2"
  local out="$3"

  if [[ "${tool_name}" == "jira_create_issue" ]]; then
    sanitize_jira_create_output "${args_json}" "${out}"
    return 0
  fi

  printf '%s\n' "${out}"
}

call_tool() {
  local tool_name="$1"
  local args_json="$2"

  if [[ "${tool_name}" == "jira_create_issue" ]]; then
    args_json="$(normalize_jira_create_args "${args_json}" || printf '%s' "${args_json}")"
  elif [[ "${tool_name}" == "jira_update_issue" ]]; then
    args_json="$(normalize_jira_update_args "${args_json}" || printf '%s' "${args_json}")"
  fi

  local has_explicit_token
  has_explicit_token="$(json_has_session_token "${args_json}")"
  local out
  local err_file
  err_file="$(mktemp)"
  if out="$(call_tool_once "${tool_name}" "${args_json}" 2>"${err_file}")"; then
    :
  else
    local ec="$?"
    local err_txt
    err_txt="$(cat "${err_file}")"
    rm -f "${err_file}"
    if [[ "${has_explicit_token}" == "0" ]] && [[ "$(is_auth_error_text "${err_txt}")" == "1" ]]; then
      login >/dev/null
      out="$(call_tool_once "${tool_name}" "${args_json}")"
      if [[ "${tool_name}" == "jira_create_issue" ]]; then
        postprocess_jira_create "${args_json}" "${out}"
      fi
      emit_tool_output "${tool_name}" "${args_json}" "${out}"
      return
    fi
    printf '%s' "${err_txt}" >&2
    return "${ec}"
  fi
  rm -f "${err_file}"
  if [[ "${has_explicit_token}" == "0" ]] && [[ "$(is_auth_error_text "${out}")" == "1" ]]; then
    login >/dev/null
    out="$(call_tool_once "${tool_name}" "${args_json}")"
    if [[ "${tool_name}" == "jira_create_issue" ]]; then
      postprocess_jira_create "${args_json}" "${out}"
    fi
    emit_tool_output "${tool_name}" "${args_json}" "${out}"
    return
  fi

  if [[ "${tool_name}" == "jira_create_issue" ]]; then
    postprocess_jira_create "${args_json}" "${out}"
  fi
  emit_tool_output "${tool_name}" "${args_json}" "${out}"
}

tools_names() {
  local raw
  raw="$(tools_list)"
  python3 - <<'PY' "${raw}"
import json
import sys
obj = json.loads(sys.argv[1])
for tool in ((obj.get("result") or {}).get("tools") or []):
    name = tool.get("name")
    if name:
        print(name)
PY
}

has_tool() {
  local pattern="${1:?regex required}"
  local names
  names="$(tools_names || true)"
  if [[ -z "${names}" ]]; then
    echo "false"
    return 1
  fi
  if printf '%s\n' "${names}" | grep -E -q -- "${pattern}"; then
    echo "true"
    return 0
  fi
  echo "false"
  return 1
}

cmd="${1:-}"
case "${cmd}" in
  login)
    login
    ;;
  tools)
    tools_list
    ;;
  tools-names)
    tools_names
    ;;
  has-tool)
    if [[ $# -lt 2 ]]; then
      usage
      exit 1
    fi
    has_tool "$2"
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
