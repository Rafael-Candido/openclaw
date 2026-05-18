#!/usr/bin/env bash
# Fast path deterministico para pedidos Jira feitos ao Lucas/Einstein no Discord.
#
# Objetivo: comandos transacionais previsiveis ("crie tarefa", "retorne para
# backlog") nao devem depender de LLM quando o gateway/modelos estiverem
# degradados.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}"
STATE_FILE="${OPENCLAW_CONFIG_DIR}/.cache/einstein-jira-fastpath-state.json"
MCP_SCRIPT="${PROJECT_ROOT}/workspace/scripts/smartenvios-mcp.sh"
JIRA_HELPER="${PROJECT_ROOT}/workspace/agents/einstein/scripts/jira-helper.sh"

CHANNELS_RAW="${GOV_EINSTEIN_CHANNEL_IDS:-690598219587256420}"
BOT_ID="${GOV_EINSTEIN_BOT_ID:-1439351480514646087}"
HISTORY_LIMIT="${EINSTEIN_JIRA_FASTPATH_HISTORY_LIMIT:-30}"
WINDOW_MIN="${EINSTEIN_JIRA_FASTPATH_WINDOW_MIN:-240}"
MAX_PER_RUN="${EINSTEIN_JIRA_FASTPATH_MAX_PER_RUN:-6}"
DRY_RUN="${EINSTEIN_JIRA_FASTPATH_DRY_RUN:-false}"

if [[ ! -x "${MCP_SCRIPT}" ]]; then
  echo '{"ok":false,"error":"mcp_script_missing"}'
  exit 1
fi

mkdir -p "$(dirname "${STATE_FILE}")"
if [[ ! -f "${STATE_FILE}" ]]; then
  printf '{"processed":{}}\n' > "${STATE_FILE}"
fi

json_escape() {
  jq -Rsa . <<<"${1:-}"
}

normalize_space() {
  tr '\n\r\t' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

state_has() {
  local message_id="$1"
  jq -e --arg id "${message_id}" '.processed[$id] != null' "${STATE_FILE}" >/dev/null 2>&1
}

state_mark() {
  local message_id="$1"
  local action="$2"
  local status="$3"
  local issue_key="${4:-}"
  local note="${5:-}"
  local tmp

  tmp="$(mktemp)"
  jq \
    --arg id "${message_id}" \
    --arg action "${action}" \
    --arg status "${status}" \
    --arg issueKey "${issue_key}" \
    --arg note "${note}" \
    --arg at "$(TZ=UTC date '+%Y-%m-%dT%H:%M:%SZ')" \
    '
      .processed[$id] = {
        at: $at,
        action: $action,
        status: $status,
        issueKey: $issueKey,
        note: $note
      }
    ' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

send_discord() {
  local channel_id="$1"
  local message="$2"

  if [[ "${DRY_RUN}" == "true" ]]; then
    return 0
  fi

  openclaw message send \
    --channel discord \
    --target "${channel_id}" \
    --message "${message}" \
    --json >/dev/null
}

resolve_assignee() {
  local raw_name="$1"
  if [[ -x "${JIRA_HELPER}" ]]; then
    "${JIRA_HELPER}" assignee-resolve "${raw_name}" 2>/dev/null || true
  fi
}

classify_payload() {
  local summary="$1"
  local description="$2"
  local reason="$3"

  if [[ -x "${JIRA_HELPER}" ]]; then
    "${JIRA_HELPER}" classify \
      --summary "${summary}" \
      --description "${description}" \
      --reason "${reason}" 2>/dev/null | jq -c '.classification // {}' 2>/dev/null || true
  fi
}

semantic_overrides() {
  local text="$1"
  python3 - "${text}" <<'PY'
import json
import re
import sys
import unicodedata

raw = sys.argv[1] if len(sys.argv) > 1 else ""
norm = raw.lower()
norm = "".join(c for c in unicodedata.normalize("NFD", norm) if not unicodedata.combining(c))

out = {}

if re.search(r"\b(romaneio|romaneios|lista de embalagem|lista de separacao|packing|picking|expedicao)\b", norm):
    out.update({
        "product": "Expedição express",
        "project_label": "Portal",
        "component": "ms.expedition-hub",
        "category": "Operacao",
    })
elif re.search(r"\bcrm\b", norm):
    out.update({
        "product": "CRM - Franquias",
        "project_label": "Não se aplica",
        "component": "lc.crm",
        "category": "Operacao",
    })
elif re.search(r"\btracking|rastreio|rastreamento\b", norm):
    out.update({
        "product": "Tracking",
        "project_label": "Não se aplica",
        "component": "ms.tracking",
        "category": "Operacao",
    })

print(json.dumps(out, ensure_ascii=False))
PY
}

extract_candidates() {
  local channel_id="$1"
  local read_json="$2"
  local tmp_read

  tmp_read="$(mktemp)"
  printf '%s' "${read_json}" > "${tmp_read}"

  python3 - "${BOT_ID}" "${WINDOW_MIN}" "${channel_id}" "${tmp_read}" <<'PY'
import json
import re
import sys
import time
import unicodedata
from pathlib import Path

bot_id = str(sys.argv[1])
window_min = max(1, int(float(sys.argv[2])))
channel_id = str(sys.argv[3])
read_path = Path(sys.argv[4])
now_ms = int(time.time() * 1000)
window_ms = window_min * 60 * 1000

try:
    data = json.loads(read_path.read_text(encoding="utf-8") or "{}")
except Exception:
    data = {}

payload = data.get("payload") if isinstance(data, dict) else {}
messages = payload.get("messages") if isinstance(payload, dict) else []
if not isinstance(messages, list):
    messages = []

def ts(msg):
    try:
        return int(msg.get("timestampMs") or 0)
    except Exception:
        return 0

def is_bot(msg):
    author = msg.get("author") or {}
    return str(author.get("id") or "") == bot_id or bool(author.get("bot"))

def content(msg):
    value = msg.get("content")
    return value if isinstance(value, str) else ""

def has_bot_mention(msg):
    mentions = msg.get("mentions") or []
    if isinstance(mentions, list):
        for mention in mentions:
            if isinstance(mention, dict) and str(mention.get("id") or "") == bot_id:
                return True
    text = content(msg)
    return f"<@{bot_id}>" in text or f"<@!{bot_id}>" in text

def strip_mentions(text):
    text = re.sub(r"<@!?\d+>", " ", text or "")
    text = re.sub(r"\s+", " ", text).strip()
    return text

def norm(text):
    text = (text or "").lower()
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", text).strip()

def author_name(msg):
    author = msg.get("author") or {}
    return str(author.get("global_name") or author.get("username") or "Solicitante").strip()

def author_id(msg):
    author = msg.get("author") or {}
    return str(author.get("id") or "").strip()

def bot_replied_after(idx, kind, issue_key=""):
    author = author_id(messages[idx])
    msg_ts = ts(messages[idx])
    for nxt in messages:
        nts = ts(nxt)
        if nts <= msg_ts:
            continue
        if not is_bot(nxt):
            continue
        txt = content(nxt)
        txt_n = norm(txt)
        if issue_key and issue_key.lower() in txt.lower() and ("backlog" in txt_n or "movida" in txt_n or "retornada" in txt_n):
            return True
        if kind == "create" and ("atividade criada" in txt_n or "key: sme-" in txt_n):
            if author and (f"<@{author}>" in txt or f"<@!{author}>" in txt):
                return True
    return False

def parse_create(text, msg):
    visible = strip_mentions(text)
    n = norm(visible)
    if not re.search(r"\b(crie|criar|abra|abrir|gere|gerar|registre|registrar)\b", n):
        return None
    if not re.search(r"\b(atividade|tarefa|task|card|chamado|ticket)\b", n):
        return None

    assignee = author_name(msg)
    scope = ""

    m = re.search(
        r"\b(?:atividade|tarefa|task|card|chamado|ticket)\b\s+(?:pra|para)\s+(mim|[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ' .-]{1,80}?)\s+(?:pra|para)\s+(.+)$",
        visible,
        flags=re.I,
    )
    if m:
        assignee_raw = m.group(1).strip(" .,")
        if norm(assignee_raw) not in {"mim", "eu"}:
            assignee = assignee_raw
        scope = m.group(2).strip(" .")
    else:
        m = re.search(
            r"\b(?:atividade|tarefa|task|card|chamado|ticket)\b(?:\s+(?:pra|para)\s+mim)?\s+(?:pra|para|sobre|de)\s+(.+)$",
            visible,
            flags=re.I,
        )
        if m:
            scope = m.group(1).strip(" .")

    if not scope:
        m = re.search(r"\b(?:atividade|tarefa|task|card|chamado|ticket)\b\s+(.+)$", visible, flags=re.I)
        if m:
            scope = m.group(1).strip(" .")

    scope = re.sub(r"^(pra|para)\s+", "", scope, flags=re.I).strip(" .")
    if not scope:
        return None

    summary = scope[:1].upper() + scope[1:]
    if len(summary) > 120:
        summary = summary[:117].rstrip() + "..."

    return {
        "kind": "create",
        "summary": summary,
        "assigneeName": assignee,
        "requestText": visible,
    }

def parse_backlog(text):
    visible = strip_mentions(text)
    n = norm(visible)
    m = re.search(r"\b(SME-\d+)\b", visible, flags=re.I)
    if not m:
        return None
    if "backlog" not in n:
        return None
    if not re.search(r"\b(retorne|retornar|volte|voltar|mova|mover|mande|enviar)\b", n):
        return None
    return {
        "kind": "backlog",
        "issueKey": m.group(1).upper(),
        "requestText": visible,
    }

filtered = [
    (idx, msg)
    for idx, msg in enumerate(messages)
    if isinstance(msg, dict)
    and ts(msg) > 0
    and (now_ms - ts(msg)) <= window_ms
]
filtered.sort(key=lambda pair: ts(pair[1]))
messages = [msg for _, msg in filtered]

out = []
for idx, msg in enumerate(messages):
    if is_bot(msg) or not has_bot_mention(msg):
        continue
    text = content(msg)
    parsed = parse_backlog(text) or parse_create(text, msg)
    if not parsed:
        continue
    if bot_replied_after(idx, parsed["kind"], parsed.get("issueKey", "")):
        parsed["alreadyAnswered"] = True
    parsed.update({
        "channelId": channel_id,
        "messageId": str(msg.get("id") or ""),
        "authorId": author_id(msg),
        "authorName": author_name(msg),
        "timestampMs": ts(msg),
    })
    out.append(parsed)

print(json.dumps(out, ensure_ascii=False))
PY

  rm -f "${tmp_read}"
}

create_issue_for_candidate() {
  local item="$1"
  local channel_id message_id author_id author_name summary assignee_name request_text

  channel_id="$(jq -r '.channelId' <<<"${item}")"
  message_id="$(jq -r '.messageId' <<<"${item}")"
  author_id="$(jq -r '.authorId' <<<"${item}")"
  author_name="$(jq -r '.authorName' <<<"${item}")"
  summary="$(jq -r '.summary' <<<"${item}")"
  assignee_name="$(jq -r '.assigneeName' <<<"${item}")"
  request_text="$(jq -r '.requestText' <<<"${item}")"

  local assignee_json account_id display_name
  assignee_json="$(resolve_assignee "${assignee_name}")"
  account_id="$(jq -r '.accountId // empty' <<<"${assignee_json}" 2>/dev/null || true)"
  display_name="$(jq -r '.displayName // empty' <<<"${assignee_json}" 2>/dev/null || true)"
  [[ -n "${display_name}" ]] || display_name="${assignee_name}"

  local reason issue_type
  reason="tarefa"
  issue_type="Task"
  if grep -Eiq '\b(erro|bug|falha|problema|quebrad|incidente)\b' <<<"${summary} ${request_text}"; then
    reason="bug"
    issue_type="Bug"
  fi
  local display_issue_type="Tarefa"
  if [[ "${issue_type}" == "Bug" ]]; then
    display_issue_type="Bug"
  fi

  local description
  description="## Solicitação do usuário:
${author_name}
${request_text}

## Objetivo
- Executar a demanda solicitada com resultado verificável.
- Validar o fluxo impactado e corrigir inconsistências relacionadas.
- Registrar evidências da validação funcional na issue.

## Critérios de aceite
- Escopo executado conforme solicitação.
- Fluxos impactados validados sem regressão.
- Evidências da validação funcional registradas na issue.
- Caso falte dado operacional, o bloqueio fica documentado na issue."

  local classification overrides payload
  classification="$(classify_payload "${summary}" "${description}" "${reason}")"
  [[ -n "${classification}" ]] || classification='{}'
  overrides="$(semantic_overrides "${summary} ${description}")"

  payload="$(
    jq -nc \
      --arg summary "${summary}" \
      --arg description "${description}" \
      --arg issueType "${issue_type}" \
      --arg priority "Highest" \
      --arg assigneeName "${display_name}" \
      --arg accountId "${account_id}" \
      --argjson c "${classification}" \
      --argjson o "${overrides}" \
      '
      {
        summary: $summary,
        description: $description,
        issue_type: $issueType,
        priority: $priority,
        assignee_name: $assigneeName
      }
      | if $accountId != "" then .account_id = $accountId else . end
      | .product = ($o.product // $c.product // "")
      | .project_label = ($o.project_label // $c.projectLabel // "")
      | .integration = ($o.integration // $c.integration // "")
      | .category = ($o.category // $c.category // "")
      | .component = ($o.component // $c.component // "")
      '
  )"

  local create_out create_text issue_key link
  create_out="$("${MCP_SCRIPT}" call jira_create_issue "${payload}")"
  create_text="$(jq -r '.result.content[0].text // "{}"' <<<"${create_out}" 2>/dev/null || echo '{}')"
  issue_key="$(jq -r '.key // empty' <<<"${create_text}" 2>/dev/null || true)"
  link="$(jq -r '.link // empty' <<<"${create_text}" 2>/dev/null || true)"

  if [[ -z "${issue_key}" ]]; then
    state_mark "${message_id}" "create" "error" "" "create_without_key"
    return 1
  fi

  local mention="<@${author_id}>"
  if [[ ! "${author_id}" =~ ^[0-9]+$ ]]; then
    mention="@${author_name}"
  fi
  [[ -n "${link}" ]] || link="https://smartenv.atlassian.net/browse/${issue_key}"

  send_discord "${channel_id}" "${mention} Atividade criada no Jira.
Key: ${issue_key}
Responsável: ${display_name}
Tipo/Prioridade: ${display_issue_type} / Highest
Link: ${link}"

  state_mark "${message_id}" "create" "ok" "${issue_key}" "created"
  echo "{\"action\":\"create\",\"messageId\":\"${message_id}\",\"issueKey\":\"${issue_key}\",\"status\":\"ok\"}"
}

transition_backlog_for_candidate() {
  local item="$1"
  local channel_id message_id author_id author_name issue_key

  channel_id="$(jq -r '.channelId' <<<"${item}")"
  message_id="$(jq -r '.messageId' <<<"${item}")"
  author_id="$(jq -r '.authorId' <<<"${item}")"
  author_name="$(jq -r '.authorName' <<<"${item}")"
  issue_key="$(jq -r '.issueKey' <<<"${item}")"

  "${MCP_SCRIPT}" call jira_transition_issue "$(jq -nc --arg key "${issue_key}" '{issue_key:$key, transition_name:"Backlog"}')" >/dev/null

  local issue_out status
  issue_out="$("${MCP_SCRIPT}" call jira_get_issue "$(jq -nc --arg key "${issue_key}" '{issue_key:$key}')")"
  status="$(jq -r '.result.content[0].text | fromjson | .fields.status.name // empty' <<<"${issue_out}" 2>/dev/null || true)"

  local mention="<@${author_id}>"
  if [[ ! "${author_id}" =~ ^[0-9]+$ ]]; then
    mention="@${author_name}"
  fi

  send_discord "${channel_id}" "${mention} Atividade retornada para o Backlog.
Key: ${issue_key}
Status: ${status:-Backlog}
Link: https://smartenv.atlassian.net/browse/${issue_key}"

  state_mark "${message_id}" "backlog" "ok" "${issue_key}" "transitioned"
  echo "{\"action\":\"backlog\",\"messageId\":\"${message_id}\",\"issueKey\":\"${issue_key}\",\"status\":\"ok\"}"
}

processed_count=0
created_count=0
transitioned_count=0
skipped_count=0
errors_count=0
results_file="$(mktemp)"
trap 'rm -f "${results_file}"' EXIT

IFS=',' read -r -a channels <<<"${CHANNELS_RAW}"
for raw_channel in "${channels[@]}"; do
  channel_id="$(echo "${raw_channel}" | tr -d '[:space:]')"
  [[ -z "${channel_id}" ]] && continue

  read_json="$(openclaw message read --channel discord --target "${channel_id}" --limit "${HISTORY_LIMIT}" --json 2>/dev/null || echo '{}')"
  candidates="$(extract_candidates "${channel_id}" "${read_json}")"

  while IFS= read -r encoded; do
    [[ -z "${encoded}" ]] && continue
    item="$(python3 - "${encoded}" <<'PY'
import base64
import sys
print(base64.b64decode(sys.argv[1]).decode("utf-8"))
PY
)"
    message_id="$(jq -r '.messageId // empty' <<<"${item}")"
    already_answered="$(jq -r '.alreadyAnswered // false' <<<"${item}")"
    kind="$(jq -r '.kind // empty' <<<"${item}")"

    [[ -z "${message_id}" ]] && continue
    if state_has "${message_id}"; then
      skipped_count=$((skipped_count + 1))
      continue
    fi
    if [[ "${already_answered}" == "true" ]]; then
      state_mark "${message_id}" "${kind}" "skipped" "" "already_answered"
      skipped_count=$((skipped_count + 1))
      continue
    fi
    if (( processed_count >= MAX_PER_RUN )); then
      break
    fi

    if [[ "${kind}" == "create" ]]; then
      if create_issue_for_candidate "${item}" >> "${results_file}"; then
        created_count=$((created_count + 1))
      else
        errors_count=$((errors_count + 1))
      fi
    elif [[ "${kind}" == "backlog" ]]; then
      if transition_backlog_for_candidate "${item}" >> "${results_file}"; then
        transitioned_count=$((transitioned_count + 1))
      else
        state_mark "${message_id}" "backlog" "error" "$(jq -r '.issueKey // empty' <<<"${item}")" "transition_failed"
        errors_count=$((errors_count + 1))
      fi
    fi
    processed_count=$((processed_count + 1))
  done < <(jq -r '.[]? | @base64' <<<"${candidates}" 2>/dev/null)
done

jq -n \
  --argjson processed "${processed_count}" \
  --argjson created "${created_count}" \
  --argjson transitioned "${transitioned_count}" \
  --argjson skipped "${skipped_count}" \
  --argjson errors "${errors_count}" \
  --slurpfile results <(jq -s '.' "${results_file}" 2>/dev/null || echo '[]') \
  '{
    ok: ($errors == 0),
    processed: $processed,
    created: $created,
    transitioned: $transitioned,
    skipped: $skipped,
    errors: $errors,
    results: ($results[0] // [])
  }'
