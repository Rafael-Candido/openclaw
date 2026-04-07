#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_DIR="${AGENT_DIR}/.pi"
ASSIGNEE_CACHE="${STATE_DIR}/jira-assignees.json"
FIELD_CACHE="${STATE_DIR}/jira-field-cache.json"
LEARNING_CACHE="${STATE_DIR}/jira-classification-learning.json"
LEARNING_EVENTS="${STATE_DIR}/jira-classification-events.jsonl"
# Usar config dir do projeto; fallback para deploy padrão
OPENCLAW_ROOT="${OPENCLAW_CONFIG_DIR:-$(cd "${SCRIPT_DIR}/../../../.." 2>/dev/null && pwd)}"
[[ -z "$OPENCLAW_ROOT" ]] && OPENCLAW_ROOT="/var/www/openclaw"
ENV_FILE="${OPENCLAW_ROOT}/.env"

AUTH_BASIC=""
JIRA_BASE_URL=""
JIRA_PROJECT_KEY_LOCAL=""

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

die() {
  echo "Erro: $*" >&2
  exit 1
}

lower() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_alias() {
  python3 - "$1" <<'PY'
import re
import sys
import unicodedata

raw = sys.argv[1] if len(sys.argv) > 1 else ""
text = raw.lower()
text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
text = re.sub(r"\s+", " ", text).strip()
print(text)
PY
}

is_not_applicable_value() {
  local normalized
  normalized="$(normalize_alias "$1")"
  case "$normalized" in
    ""|"nao se aplica"|"n/a"|"none"|"null"|"sem classificacao"|"na"|"nenhum"|"nenhuma")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

build_adf_description() {
  local raw="${1:-}"
  python3 - "$raw" <<'PY'
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
    heading_match = re.match(r"^\s*#{1,6}\s+(.+?)\s*$", line)
    if heading_match:
        flush_bullets()
        flush_ordered()
        nodes.append(
            {
                "type": "heading",
                "attrs": {"level": 2},
                "content": [{"type": "text", "text": heading_match.group(1).strip()}],
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

is_file_stale() {
  local file="$1"
  local max_age_seconds="$2"
  local now mtime

  [[ -f "$file" ]] || return 0

  now="$(date +%s)"
  mtime="$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)"
  (( now - mtime > max_age_seconds ))
}

init_state() {
  mkdir -p "$STATE_DIR"

  if [[ ! -f "$ASSIGNEE_CACHE" ]]; then
    cat > "$ASSIGNEE_CACHE" <<'JSON'
{
  "updatedAt": null,
  "aliases": {},
  "usersByAccountId": {}
}
JSON
  fi

  if [[ ! -f "$FIELD_CACHE" ]]; then
    cat > "$FIELD_CACHE" <<'JSON'
{
  "updatedAt": null,
  "fieldIds": {
    "product": "",
    "integration": "",
    "category": "",
    "projectLabel": ""
  }
}
JSON
  fi

  if [[ ! -f "$LEARNING_CACHE" ]]; then
    cat > "$LEARNING_CACHE" <<'JSON'
{
  "updatedAt": null,
  "minScore": 2,
  "globalCounts": {
    "product": {},
    "integration": {},
    "category": {},
    "projectLabel": {},
    "component": {}
  },
  "tokensByField": {
    "product": {},
    "integration": {},
    "category": {},
    "projectLabel": {},
    "component": {}
  }
}
JSON
  fi

  if [[ ! -f "$LEARNING_EVENTS" ]]; then
    : > "$LEARNING_EVENTS"
  fi
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Arquivo .env nao encontrado em $ENV_FILE"

  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a

  : "${JIRA_BASE_URL:?JIRA_BASE_URL ausente no .env}"
  : "${JIRA_EMAIL:?JIRA_EMAIL ausente no .env}"
  : "${JIRA_API_TOKEN:?JIRA_API_TOKEN ausente no .env}"
  : "${JIRA_PROJECT_KEY:?JIRA_PROJECT_KEY ausente no .env}"

  JIRA_BASE_URL="${JIRA_BASE_URL%/}/"
  JIRA_PROJECT_KEY_LOCAL="${JIRA_PROJECT_KEY}"
  AUTH_BASIC="$(printf "%s:%s" "${JIRA_EMAIL}" "${JIRA_API_TOKEN}" | base64 | tr -d '\n')"
}

jira_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url http_code tmp_body

  url="${JIRA_BASE_URL}${path}"
  tmp_body="$(mktemp)"

  if [[ -n "$body" ]]; then
    http_code="$(
      curl -sS -o "$tmp_body" -w "%{http_code}" -X "$method" "$url" \
        -H "Authorization: Basic ${AUTH_BASIC}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        --data "$body"
    )"
  else
    http_code="$(
      curl -sS -o "$tmp_body" -w "%{http_code}" -X "$method" "$url" \
        -H "Authorization: Basic ${AUTH_BASIC}" \
        -H "Accept: application/json"
    )"
  fi

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "Jira API error ${http_code} em ${method} ${path}" >&2
    cat "$tmp_body" >&2
    rm -f "$tmp_body"
    return 1
  fi

  cat "$tmp_body"
  rm -f "$tmp_body"
}

jira_get() {
  jira_request "GET" "$1"
}

jira_post() {
  jira_request "POST" "$1" "$2"
}

cache_user_object() {
  local user_json="$1"
  local query_alias="${2:-}"
  local account_id display_name email normalized_display normalized_first tmp_file

  account_id="$(jq -r '.accountId // empty' <<<"$user_json")"
  [[ -n "$account_id" ]] || return 0

  display_name="$(jq -r '.displayName // empty' <<<"$user_json")"
  email="$(jq -r '.emailAddress // empty' <<<"$user_json")"
  normalized_display="$(normalize_alias "$display_name")"
  normalized_first="$(normalize_alias "${display_name%% *}")"

  tmp_file="$(mktemp)"
  jq \
    --arg accountId "$account_id" \
    --arg displayName "$display_name" \
    --arg email "$email" \
    --arg now "$(now_iso)" \
    --arg normalizedDisplay "$normalized_display" \
    --arg normalizedFirst "$normalized_first" \
    '
      .updatedAt = $now
      | .usersByAccountId[$accountId] = {
          accountId: $accountId,
          displayName: $displayName,
          emailAddress: $email,
          lastSeenAt: $now
      }
      | if $normalizedDisplay != "" then .aliases[$normalizedDisplay] = $accountId else . end
      | if $normalizedFirst != "" then .aliases[$normalizedFirst] = $accountId else . end
      | if $email != "" then .aliases[($email | ascii_downcase)] = $accountId else . end
      | if $email != "" then .aliases[(($email | split("@")[0]) | ascii_downcase)] = $accountId else . end
    ' "$ASSIGNEE_CACHE" > "$tmp_file"

  mv "$tmp_file" "$ASSIGNEE_CACHE"
}

resolve_assignee() {
  local query="$1"
  local normalized_query account_id cached_user uri search_results selected tmp_file

  normalized_query="$(normalize_alias "$query")"
  account_id="$(jq -r --arg alias "$normalized_query" '.aliases[$alias] // empty' "$ASSIGNEE_CACHE")"

  if [[ -n "$account_id" ]]; then
    cached_user="$(jq -c --arg id "$account_id" '.usersByAccountId[$id] // {}' "$ASSIGNEE_CACHE")"
    if [[ "$cached_user" != "{}" ]] && assignee_matches_query "$query" "$cached_user"; then
      jq -c '. + {source: "cache"}' <<<"$cached_user"
      return 0
    fi
  fi

  uri="$(urlencode "$query")"
  search_results="$(jira_get "rest/api/3/user/search?query=${uri}&maxResults=50")"

  while IFS= read -r user_line; do
    cache_user_object "$user_line" "$query"
  done < <(jq -c '.[]' <<<"$search_results")

  # Após popular cache com resultados da API, tenta novamente por alias normalizado.
  account_id="$(jq -r --arg alias "$normalized_query" '.aliases[$alias] // empty' "$ASSIGNEE_CACHE")"
  if [[ -n "$account_id" ]]; then
    cached_user="$(jq -c --arg id "$account_id" '.usersByAccountId[$id] // {}' "$ASSIGNEE_CACHE")"
    if [[ "$cached_user" != "{}" ]] && assignee_matches_query "$query" "$cached_user"; then
      jq -c '. + {source: "api-cache"}' <<<"$cached_user"
      return 0
    fi
  fi

  selected="$(jq -c --arg q "$normalized_query" '
    def norm: tostring | ascii_downcase;
    if (type != "array" or length == 0) then
      null
    else
      (
        map(select(
          ((.displayName // "" | norm) == $q)
          or ((.emailAddress // "" | norm) == $q)
          or ((((.emailAddress // "") | split("@")[0]) | norm) == $q)
        ))[0]
        // map(select(
          ((.displayName // "" | norm) | contains($q))
          or ((.emailAddress // "" | norm) | contains($q))
        ))[0]
      )
    end
  ' <<<"$search_results")"

  [[ "$selected" != "null" && -n "$selected" ]] || return 1

  cache_user_object "$selected" "$query"

  # Apenas o usuário escolhido recebe alias da consulta textual.
  account_id="$(jq -r '.accountId // empty' <<<"$selected")"
  if [[ -n "$account_id" && -n "$normalized_query" ]]; then
    tmp_file="$(mktemp)"
    jq --arg alias "$normalized_query" --arg id "$account_id" '.aliases[$alias] = $id' "$ASSIGNEE_CACHE" > "$tmp_file"
    mv "$tmp_file" "$ASSIGNEE_CACHE"
  fi

  jq -c '. + {source: "api"}' <<<"$selected"
}

resolve_assignee_from_cache_only() {
  local query="$1"
  local normalized_query account_id cached_user

  normalized_query="$(normalize_alias "$query")"
  account_id="$(jq -r --arg alias "$normalized_query" '.aliases[$alias] // empty' "$ASSIGNEE_CACHE")"
  [[ -n "$account_id" ]] || return 1

  cached_user="$(jq -c --arg id "$account_id" '.usersByAccountId[$id] // {}' "$ASSIGNEE_CACHE")"
  [[ "$cached_user" != "{}" ]] || return 1
  assignee_matches_query "$query" "$cached_user" || return 1

  jq -c '. + {source: "cache"}' <<<"$cached_user"
}

assignee_matches_query() {
  local query="$1"
  local user_json="$2"
  local q_norm display_norm email_local_norm token

  q_norm="$(normalize_alias "$query")"
  [[ -n "$q_norm" ]] || return 1

  display_norm="$(normalize_alias "$(jq -r '.displayName // ""' <<<"$user_json")")"
  email_local_norm="$(normalize_alias "$(jq -r '.emailAddress // ""' <<<"$user_json" | awk -F'@' '{print $1}')")"

  for token in $q_norm; do
    [[ ${#token} -ge 2 ]] || continue
    if [[ "$display_norm" == *"$token"* || "$email_local_norm" == *"$token"* ]]; then
      continue
    fi
    return 1
  done
  return 0
}

sync_field_ids() {
  local fields_json product_id integration_id category_id project_label_id tmp_file

  fields_json="$(jira_get "rest/api/3/field")"

  product_id="$(jq -r '
    map(select(
      .custom == true
      and ((.name // "" | ascii_downcase) | test("^(produto|product)(\\b|\\s|$)"))
    ))
    | .[0].id // ""
  ' <<<"$fields_json")"

  integration_id="$(jq -r '
    map(select(.custom == true and ((.name // "" | ascii_downcase) | test("integra|integration|transportadora|carrier"))))
    | .[0].id // ""
  ' <<<"$fields_json")"

  category_id="$(jq -r '
    map(select(.custom == true and ((.name // "" | ascii_downcase) | test("categoria|category"))))
    | .[0].id // ""
  ' <<<"$fields_json")"

  project_label_id="$(jq -r '
    map(select(.custom == true and ((.name // "" | ascii_downcase) | test("projeto|project"))))
    | .[0].id // ""
  ' <<<"$fields_json")"

  tmp_file="$(mktemp)"
  jq -n \
    --arg updatedAt "$(now_iso)" \
    --arg product "$product_id" \
    --arg integration "$integration_id" \
    --arg category "$category_id" \
    --arg projectLabel "$project_label_id" \
    '{
      updatedAt: $updatedAt,
      fieldIds: {
        product: $product,
        integration: $integration,
        category: $category,
        projectLabel: $projectLabel
      }
    }' > "$tmp_file"

  mv "$tmp_file" "$FIELD_CACHE"
}

maybe_sync_field_ids() {
  if is_file_stale "$FIELD_CACHE" 86400; then
    sync_field_ids
  fi
}

learn_field_value() {
  local field="$1"
  local value="$2"
  local context="$3"
  local now_ts context_excerpt value_norm

  now_ts="$(now_iso)"
  value_norm="$(normalize_alias "$value")"
  if [[ -z "$value_norm" ]]; then
    return 0
  fi
  if [[ "$value_norm" =~ ^(nao\ se\ aplica|n/a|none|sem\ classificacao|na|null|nenhum|nenhuma)$ ]]; then
    return 0
  fi

  python3 - "$LEARNING_CACHE" "$field" "$value" "$context" "$now_ts" <<'PY' >/dev/null
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

cache_path = Path(sys.argv[1])
field = (sys.argv[2] or "").strip()
value = (sys.argv[3] or "").strip()
context = sys.argv[4] or ""
now_ts = sys.argv[5] or ""

valid_fields = {"product", "integration", "category", "projectLabel", "component"}
if field not in valid_fields:
    raise SystemExit(0)

def default_payload():
    return {
        "updatedAt": None,
        "minScore": 2,
        "globalCounts": {k: {} for k in valid_fields},
        "tokensByField": {k: {} for k in valid_fields},
    }

def norm(text: str) -> str:
    text = text.lower()
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
    text = re.sub(r"\s+", " ", text).strip()
    return text

def tokenize(text: str):
    stopwords = {
        "para","com","sem","por","das","dos","que","uma","uns","uma","de","da","do","no","na","nos","nas",
        "em","ao","aos","e","ou","se","ser","sao","foi","tem","ter","como","mais","menos","muito","muita",
        "muitas","muitos","sobre","entre","apos","antes","quando","onde","qual","quais","isso","isto","esse",
        "essa","esse","essa","ele","ela","eles","elas","nosso","nossa","suas","seus","ja","ainda","pra",
        "favor","cliente","solicitacao","atividade","tarefa","jira","criar","crie","issue","task","story",
        "bug","melhoria","ajuste","demanda","status","todo","high","highest","medium","low","pendente",
    }
    text = norm(text)
    text = re.sub(r"[^a-z0-9._-]+", " ", text)
    parts = [p.strip("._-") for p in text.split()]
    out = []
    seen = set()
    for token in parts:
        if not token:
            continue
        if token in stopwords:
            continue
        if token.isdigit():
            continue
        if len(token) < 3 and "." not in token:
            continue
        if token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out

if not value:
    raise SystemExit(0)

value_norm = norm(value)
if value_norm in {"nao se aplica", "n/a", "none", "sem classificacao", "na", "null", "nenhum", "nenhuma"}:
    raise SystemExit(0)

try:
    data = json.loads(cache_path.read_text(encoding="utf-8"))
except Exception:
    data = default_payload()

if not isinstance(data, dict):
    data = default_payload()

global_counts = data.setdefault("globalCounts", {})
tokens_by_field = data.setdefault("tokensByField", {})
field_globals = global_counts.setdefault(field, {})
field_tokens = tokens_by_field.setdefault(field, {})

field_globals[value] = int(field_globals.get(value, 0)) + 1

for token in tokenize(context):
    token_bucket = field_tokens.setdefault(token, {})
    token_bucket[value] = int(token_bucket.get(value, 0)) + 1

data["updatedAt"] = now_ts or data.get("updatedAt")

tmp_path = cache_path.with_suffix(cache_path.suffix + ".tmp")
tmp_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
os.replace(tmp_path, cache_path)
PY

  context_excerpt="${context:0:600}"
  jq -cn \
    --arg at "$now_ts" \
    --arg field "$field" \
    --arg value "$value" \
    --arg context "$context_excerpt" \
    '{at: $at, field: $field, value: $value, context: $context}' >> "$LEARNING_EVENTS"
}

predict_field_from_learning() {
  local field="$1"
  local context="$2"
  [[ -f "$LEARNING_CACHE" ]] || return 0

  python3 - "$LEARNING_CACHE" "$field" "$context" <<'PY'
import json
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

cache_path = Path(sys.argv[1])
field = (sys.argv[2] or "").strip()
context = sys.argv[3] or ""

valid_fields = {"product", "integration", "category", "projectLabel", "component"}
if field not in valid_fields:
    print("")
    raise SystemExit(0)

def norm(text: str) -> str:
    text = text.lower()
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))
    text = re.sub(r"\s+", " ", text).strip()
    return text

def tokenize(text: str):
    stopwords = {
        "para","com","sem","por","das","dos","que","uma","uns","de","da","do","no","na","nos","nas",
        "em","ao","aos","e","ou","se","ser","sao","foi","tem","ter","como","mais","menos","muito","muita",
        "muitas","muitos","sobre","entre","apos","antes","quando","onde","qual","quais","isso","isto","esse",
        "essa","ele","ela","eles","elas","nosso","nossa","suas","seus","ja","ainda","pra","favor","cliente",
        "solicitacao","atividade","tarefa","jira","criar","crie","issue","task","story","bug","melhoria",
        "ajuste","demanda","status","todo","high","highest","medium","low","pendente",
    }
    text = norm(text)
    text = re.sub(r"[^a-z0-9._-]+", " ", text)
    parts = [p.strip("._-") for p in text.split()]
    seen = set()
    out = []
    for token in parts:
        if not token:
            continue
        if token in stopwords:
            continue
        if token.isdigit():
            continue
        if len(token) < 3 and "." not in token:
            continue
        if token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out

try:
    data = json.loads(cache_path.read_text(encoding="utf-8"))
except Exception:
    print("")
    raise SystemExit(0)

tokens_by_field = ((data or {}).get("tokensByField") or {}).get(field) or {}
global_counts = ((data or {}).get("globalCounts") or {}).get(field) or {}
min_score = int((data or {}).get("minScore", 2) or 2)

scores = defaultdict(int)
for token in tokenize(context):
    raw = tokens_by_field.get(token) or {}
    if isinstance(raw, dict):
        for value, count in raw.items():
            if not value:
                continue
            try:
                n = int(count)
            except Exception:
                continue
            if n > 0:
                scores[value] += n

if not scores:
    if isinstance(global_counts, dict) and global_counts:
        ordered = sorted(
            ((k, int(v)) for k, v in global_counts.items() if k),
            key=lambda item: item[1],
            reverse=True,
        )
        if ordered and ordered[0][1] >= 6:
            print(ordered[0][0])
            raise SystemExit(0)
    print("")
    raise SystemExit(0)

ordered_scores = sorted(scores.items(), key=lambda item: item[1], reverse=True)
top_value, top_score = ordered_scores[0]
second_score = ordered_scores[1][1] if len(ordered_scores) > 1 else 0

if top_score < min_score:
    print("")
elif top_score == second_score:
    print("")
else:
    print(top_value)
PY
}

extract_issue_field_value() {
  local issue_json="$1"
  local field_id="$2"
  [[ -n "$field_id" ]] || { echo ""; return; }

  jq -r --arg field "$field_id" '
    .fields[$field] as $value
    | if $value == null then ""
      elif ($value | type) == "string" then $value
      elif ($value | type) == "object" then ($value.value // $value.name // "")
      elif ($value | type) == "array" then
        if ($value | length) == 0 then ""
        elif ($value[0] | type) == "string" then ($value | join(", "))
        elif ($value[0] | type) == "object" then ($value[0].value // $value[0].name // "")
        else ""
        end
      else ""
      end
  ' <<<"$issue_json"
}

learn_classification_set() {
  local context="$1"
  local product="$2"
  local project_label="$3"
  local integration="$4"
  local category="$5"
  local component="$6"

  learn_field_value "product" "$product" "$context"
  learn_field_value "projectLabel" "$project_label" "$context"
  learn_field_value "integration" "$integration" "$context"
  learn_field_value "category" "$category" "$context"
  learn_field_value "component" "$component" "$context"
}

infer_issue_type() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ bug|erro|falha|defeito|nao\ atualiza|nao\ funciona|incidente|quebra|trava ]]; then
    echo "Bug"
    return
  fi

  if [[ "$text" =~ melhoria|melhorar|aprimorar|evolu|feature|otimiz ]]; then
    echo "Story"
    return
  fi

  echo "Task"
}

infer_integration() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ dhl ]]; then echo "DHL"; return; fi
  if [[ "$text" =~ correios ]]; then echo "Correios"; return; fi
  if [[ "$text" =~ jadlog ]]; then echo "Jadlog"; return; fi
  if [[ "$text" =~ loggi ]]; then echo "Loggi"; return; fi
  if [[ "$text" =~ magalog ]]; then echo "Magalog"; return; fi
  if [[ "$text" =~ total\ express|pedidos?\ da\ total|transportadora\ total ]]; then echo "Total Express"; return; fi
  if [[ "$text" =~ azul ]]; then echo "Azul Cargo"; return; fi
  if [[ "$text" =~ melhor\ envio ]]; then echo "Melhor Envio"; return; fi
  echo ""
}

infer_category() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ zendesk|ticket|chamado|atendimento ]]; then echo "Operacao"; return; fi
  if [[ "$text" =~ loggi|correios|jadlog|magalog|dhl|total\ express|transportadora ]]; then echo "Tracking"; return; fi
  if [[ "$text" =~ tracking|rastreio|rastreamento ]]; then echo "Tracking"; return; fi
  if [[ "$text" =~ etiqueta|label ]]; then echo "Etiqueta"; return; fi
  if [[ "$text" =~ cotacao|frete|quote ]]; then echo "Cotacao"; return; fi
  if [[ "$text" =~ integracao|integration|webhook ]]; then echo "Integracao"; return; fi
  if [[ "$text" =~ financeiro|fatura|cobranca ]]; then echo "Financeiro"; return; fi
  if [[ "$text" =~ login|acesso|senha ]]; then echo "Acesso"; return; fi
  echo "Operacao"
}

infer_product() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ zendesk|ticket|chamado|atendimento ]]; then echo "Atendimento"; return; fi
  if [[ "$text" =~ loggi|correios|jadlog|magalog|dhl|total\ express|transportadora ]]; then echo "Tracking"; return; fi
  if [[ "$text" =~ magento|connector|integracao|integration|plataforma ]]; then echo "Integração Plataformas"; return; fi
  if [[ "$text" =~ tracking|rastreio|rastreamento ]]; then echo "Tracking"; return; fi
  if [[ "$text" =~ dashboard|painel ]]; then echo "Dashboard"; return; fi
  echo "Não se aplica"
}

infer_project_label() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ zendesk|ticket|chamado|atendimento ]]; then echo "Zendesk"; return; fi
  if [[ "$text" =~ total\ express|pedidos?\ da\ total|transportadora\ total ]]; then echo "Connector Total Express"; return; fi
  if [[ "$text" =~ correios ]]; then echo "Connector Correios"; return; fi
  if [[ "$text" =~ loggi ]]; then echo "Connector loggi"; return; fi
  if [[ "$text" =~ jadlog ]]; then echo "Connector Jadlog"; return; fi
  if [[ "$text" =~ magalog ]]; then echo "Não se aplica"; return; fi
  if [[ "$text" =~ magento\ 2|magento2|magento ]]; then echo "Connector Magento 2"; return; fi
  if [[ "$text" =~ vtex ]]; then echo "Connector VTEX"; return; fi
  if [[ "$text" =~ shopify ]]; then echo "Connector Shopify"; return; fi
  if [[ "$text" =~ woocommerce|woo\ commerce ]]; then echo "Connector WooCommerce"; return; fi
  if [[ "$text" =~ bling ]]; then echo "Connector Bling"; return; fi
  if [[ "$text" =~ tiny ]]; then echo "Connector Tiny"; return; fi
  echo "Não se aplica"
}

infer_component() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ zendesk|ticket|chamado|atendimento ]]; then echo "ms.atendimento"; return; fi
  if [[ "$text" =~ loggi|correios|jadlog|magalog|dhl|total\ express|tracking|rastreio|rastreamento ]]; then echo "ms.tracking"; return; fi
  if [[ "$text" =~ magento|connector|integracao|integration ]]; then echo "ms.connectors"; return; fi
  if [[ "$text" =~ tracking|rastreio|rastreamento ]]; then echo "ms.tracking"; return; fi
  echo "Não se aplica"
}

to_label_slug() {
  local text
  text="$(normalize_alias "$1")"
  text="$(tr ' ' '-' <<<"$text")"
  text="$(tr -cd '[:alnum:]-_' <<<"$text")"
  text="${text#-}"
  text="${text%-}"
  echo "$text"
}

candidate_values_for_kind() {
  local kind="$1"
  local value="$2"

  local normalized
  normalized="$(normalize_alias "$value")"

  if [[ -n "$value" ]]; then
    echo "$value"
  fi

  case "$kind" in
    category)
      if [[ "$normalized" == "tracking" || "$normalized" == "rastreamento" || "$normalized" == "rastreio" ]]; then
        echo "Tracking"
        echo "Rastreamento"
        echo "Rastreio"
      fi
      if [[ "$normalized" == "integracao" || "$normalized" == "integration" ]]; then
        echo "Integracao"
        echo "Integração"
        echo "Integration"
      fi
      if [[ "$normalized" == "operacao" ]]; then
        echo "Operacao"
        echo "Operação"
      fi
      ;;
    product)
      if [[ "$normalized" == "integracao plataformas" || "$normalized" == "integracao" || "$normalized" == "integration" || "$normalized" == "magento" || "$normalized" == "magento 2" ]]; then echo "Integração Plataformas"; fi
      if [[ "$normalized" == "atendimento" || "$normalized" == "zendesk" ]]; then echo "Atendimento"; fi
      if [[ "$normalized" == "tracking" || "$normalized" == "rastreio" || "$normalized" == "rastreamento" ]]; then echo "Tracking"; fi
      if [[ "$normalized" == "nao se aplica" ]]; then echo "Não se aplica"; fi
      ;;
    projectLabel)
      if [[ "$normalized" == "magento 2" || "$normalized" == "magento" || "$normalized" == "connector magento 2" ]]; then echo "Connector Magento 2"; fi
      if [[ "$normalized" == "zendesk" || "$normalized" == "atendimento" ]]; then echo "Zendesk"; fi
      if [[ "$normalized" == "connector total express" || "$normalized" == "total express" || "$normalized" == "total" ]]; then echo "Connector Total Express"; fi
      if [[ "$normalized" == "connector correios" || "$normalized" == "correios" ]]; then echo "Connector Correios"; fi
      if [[ "$normalized" == "connector loggi" || "$normalized" == "loggi" ]]; then echo "Connector loggi"; fi
      if [[ "$normalized" == "connector jadlog" || "$normalized" == "jadlog" ]]; then echo "Connector Jadlog"; fi
      if [[ "$normalized" == "magalog" || "$normalized" == "connector magalog" ]]; then echo "Não se aplica"; fi
      if [[ "$normalized" == "nao se aplica" ]]; then echo "Não se aplica"; fi
      ;;
    component)
      if [[ "$normalized" == "ms connectors" || "$normalized" == "connectors" || "$normalized" == "connector" || "$normalized" == "magento" || "$normalized" == "magento 2" ]]; then echo "ms.connectors"; fi
      if [[ "$normalized" == "ms atendimento" || "$normalized" == "atendimento" || "$normalized" == "zendesk" ]]; then echo "ms.atendimento"; fi
      if [[ "$normalized" == "ms tracking" || "$normalized" == "tracking" || "$normalized" == "loggi" || "$normalized" == "correios" || "$normalized" == "jadlog" || "$normalized" == "magalog" || "$normalized" == "total express" ]]; then echo "ms.tracking"; fi
      if [[ "$normalized" == "nao se aplica" ]]; then echo "Não se aplica"; fi
      ;;
  esac
}

pick_allowed_value() {
  local kind="$1"
  local desired="$2"
  local allowed_json="$3"
  local required="$4"
  local chosen=""
  local candidate allowed candidate_l allowed_l
  local -a allowed_values=()
  local -a candidates=()

  while IFS= read -r allowed; do
    [[ -n "$allowed" ]] || continue
    allowed_values+=("$allowed")
  done < <(jq -r '.[] | .value // .name // empty' <<<"$allowed_json")

  if [[ "${#allowed_values[@]}" -eq 0 ]]; then
    # Sem allowedValues não há garantia de que o valor é aceito.
    # Melhor omitir e deixar o Jira aplicar default, evitando 400.
    echo ""
    return
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    candidates+=("$candidate")
  done < <(candidate_values_for_kind "$kind" "$desired" | awk 'NF' | awk '!seen[$0]++')

  for candidate in "${candidates[@]}"; do
    candidate_l="$(normalize_alias "$candidate")"
    [[ -n "$candidate_l" ]] || continue
    for allowed in "${allowed_values[@]}"; do
      allowed_l="$(normalize_alias "$allowed")"
      if [[ "$allowed_l" == "$candidate_l" || "$allowed_l" == *"$candidate_l"* || "$candidate_l" == *"$allowed_l"* ]]; then
        chosen="$allowed"
        break 2
      fi
    done
  done

  if [[ -z "$chosen" && "$required" == "true" ]]; then
    if [[ "$kind" == "projectLabel" ]]; then
      for allowed in "${allowed_values[@]}"; do
        allowed_l="$(normalize_alias "$allowed")"
        if [[ "$allowed_l" == "nao se aplica" || "$allowed_l" == "nao aplicavel" || "$allowed_l" == "n/a" ]]; then
          chosen="$allowed"
          break
        fi
      done
    fi
    [[ -n "$chosen" ]] || chosen="${allowed_values[0]}"
  fi

  echo "$chosen"
}

field_spec_from_meta() {
  local createmeta_json="$1"
  local issue_type="$2"
  local field_id="$3"

  jq -c \
    --arg issueType "$issue_type" \
    --arg fieldId "$field_id" \
    '
      (.projects[0].issuetypes // []) as $issueTypes
      | ($issueTypes | map(select((.name // "" | ascii_downcase) == ($issueType | ascii_downcase)))[0] // $issueTypes[0]) as $selected
      | if ($selected == null) then
          {required: false, allowed: []}
        else
          {
            required: ($selected.fields[$fieldId].required // false),
            allowed: ($selected.fields[$fieldId].allowedValues // []),
            schema: ($selected.fields[$fieldId].schema // {})
          }
        end
    ' <<<"$createmeta_json"
}

ensure_todo_status() {
  local issue_key="$1"
  local transitions_json target_transition_id

  transitions_json="$(jira_get "rest/api/3/issue/${issue_key}/transitions")"
  target_transition_id="$(jq -r '
    [
      .transitions[]
      | select(
          ((.to.name // "" | ascii_downcase) == "to do")
          or ((.to.name // "" | ascii_downcase) == "tarefas pendentes")
          or ((.to.name // "" | ascii_downcase) == "pendente")
          or ((.to.name // "" | ascii_downcase) == "pending")
          or ((.to.name // "" | ascii_downcase) == "backlog")
        )
    ][0].id // empty
  ' <<<"$transitions_json")"

  if [[ -n "$target_transition_id" ]]; then
    jira_post "rest/api/3/issue/${issue_key}/transitions" \
      "$(jq -n --arg id "$target_transition_id" '{transition: {id: $id}}')" >/dev/null
    echo "true"
    return
  fi

  echo "false"
}

cmd_assignee_resolve() {
  local query="${1:-}"
  [[ -n "$query" ]] || die "Uso: $0 assignee-resolve \"Nome\""

  load_env
  init_state

  resolve_assignee "$query" \
    || die "Nao foi possivel resolver assignee para \"$query\""
}

cmd_assignee_list() {
  init_state
  jq -c '.usersByAccountId' "$ASSIGNEE_CACHE"
}

cmd_sync_fields() {
  load_env
  init_state
  sync_field_ids
  jq -c '.' "$FIELD_CACHE"
}

cmd_learn_from_issue() {
  local issue_key=""
  local context=""
  local fields_query="summary,description,status,components"
  local issue_json summary_text description_text
  local product_field integration_field category_field project_label_field
  local learned_product learned_project_label learned_integration learned_category learned_component

  load_env
  init_state
  maybe_sync_field_ids

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue-key)
        issue_key="${2:-}"
        shift 2
        ;;
      --context)
        context="${2:-}"
        shift 2
        ;;
      *)
        die "Argumento desconhecido em learn-from-issue: $1"
        ;;
    esac
  done

  [[ -n "$issue_key" ]] || die "Parametro obrigatorio ausente: --issue-key"

  product_field="$(jq -r '.fieldIds.product // empty' "$FIELD_CACHE")"
  integration_field="$(jq -r '.fieldIds.integration // empty' "$FIELD_CACHE")"
  category_field="$(jq -r '.fieldIds.category // empty' "$FIELD_CACHE")"
  project_label_field="$(jq -r '.fieldIds.projectLabel // empty' "$FIELD_CACHE")"
  if [[ -n "$product_field" ]]; then fields_query+=",${product_field}"; fi
  if [[ -n "$integration_field" ]]; then fields_query+=",${integration_field}"; fi
  if [[ -n "$category_field" ]]; then fields_query+=",${category_field}"; fi
  if [[ -n "$project_label_field" ]]; then fields_query+=",${project_label_field}"; fi

  issue_json="$(jira_get "rest/api/3/issue/${issue_key}?fields=$(urlencode "$fields_query")" || echo '{}')"

  if [[ -z "$context" ]]; then
    summary_text="$(jq -r '.fields.summary // ""' <<<"$issue_json")"
    description_text="$(jq -r '[.. | objects | .text? // empty] | join(" ")' <<<"$issue_json")"
    context="$summary_text"$'\n'"$description_text"
  fi

  learned_product="$(extract_issue_field_value "$issue_json" "$product_field")"
  learned_project_label="$(extract_issue_field_value "$issue_json" "$project_label_field")"
  learned_integration="$(extract_issue_field_value "$issue_json" "$integration_field")"
  learned_category="$(extract_issue_field_value "$issue_json" "$category_field")"
  learned_component="$(extract_issue_field_value "$issue_json" "components")"

  learn_classification_set \
    "$context" \
    "$learned_product" \
    "$learned_project_label" \
    "$learned_integration" \
    "$learned_category" \
    "$learned_component"

  jq -n \
    --arg issueKey "$issue_key" \
    --arg product "$learned_product" \
    --arg projectLabel "$learned_project_label" \
    --arg integration "$learned_integration" \
    --arg category "$learned_category" \
    --arg component "$learned_component" \
    '{
      ok: true,
      issueKey: $issueKey,
      learned: {
        product: $product,
        projectLabel: $projectLabel,
        integration: $integration,
        category: $category,
        component: $component
      }
    }'
}

cmd_learning_report() {
  init_state
  jq '
    def top_values($obj):
      (($obj // {}) | to_entries | sort_by(-(.value // 0)) | .[:5]);
    def top_tokens($obj):
      (($obj // {})
      | to_entries
      | map({
          token: .key,
          total: ((.value // {}) | to_entries | map(.value // 0) | add // 0)
        })
      | sort_by(-(.total // 0))
      | .[:10]);
    {
      updatedAt,
      minScore,
      topValues: {
        product: top_values(.globalCounts.product),
        projectLabel: top_values(.globalCounts.projectLabel),
        integration: top_values(.globalCounts.integration),
        category: top_values(.globalCounts.category),
        component: top_values(.globalCounts.component)
      },
      topTokens: {
        product: top_tokens(.tokensByField.product),
        projectLabel: top_tokens(.tokensByField.projectLabel),
        integration: top_tokens(.tokensByField.integration),
        category: top_tokens(.tokensByField.category),
        component: top_tokens(.tokensByField.component)
      }
    }
  ' "$LEARNING_CACHE"
}

cmd_classify() {
  cmd_create --dry-run "$@"
}

cmd_create() {
  local summary=""
  local description=""
  local assignee_name=""
  local reason=""
  local product=""
  local integration=""
  local category=""
  local project_label=""
  local component=""
  local priority="Highest"
  local project_key=""
  local dry_run="false"
  local force_sync_fields="false"
  local issue_type=""
  local assignee_json="{}"
  local assignee_account_id=""
  local assignee_display_name=""
  local context_text=""
  local createmeta_json="{}"
  local custom_fields_json="{}"
  local issue_response issue_key issue_id issue_url status_name transitioned_to_todo
  local product_field integration_field category_field project_label_field component_field
  local product_spec integration_spec category_spec project_label_spec component_spec
  local product_required integration_required category_required project_label_required component_required
  local product_allowed integration_allowed category_allowed project_label_allowed component_allowed
  local selected_product selected_integration selected_category selected_project_label selected_component
  local learned_product learned_integration learned_category learned_project_label learned_component
  local description_text description_doc payload payload_component_json labels_json category_label
  local issue_fields_query="status,components"
  local issue_fields_json final_product final_project_label final_integration final_category final_component
  local links=()
  local append_classification_in_desc="${JIRA_HELPER_APPEND_CLASSIFICATION_IN_DESCRIPTION:-false}"

  load_env
  init_state

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --summary)
        summary="${2:-}"
        shift 2
        ;;
      --description)
        description="${2:-}"
        shift 2
        ;;
      --assignee)
        assignee_name="${2:-}"
        shift 2
        ;;
      --reason)
        reason="${2:-}"
        shift 2
        ;;
      --product)
        product="${2:-}"
        shift 2
        ;;
      --integration)
        integration="${2:-}"
        shift 2
        ;;
      --category|--categoria)
        category="${2:-}"
        shift 2
        ;;
      --project-label)
        project_label="${2:-}"
        shift 2
        ;;
      --component)
        component="${2:-}"
        shift 2
        ;;
      --priority)
        priority="${2:-}"
        shift 2
        ;;
      --project-key)
        project_key="${2:-}"
        shift 2
        ;;
      --link)
        links+=("${2:-}")
        shift 2
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --sync-fields)
        force_sync_fields="true"
        shift
        ;;
      *)
        die "Argumento desconhecido: $1"
        ;;
    esac
  done

  [[ -n "$summary" ]] || die "Parametro obrigatorio ausente: --summary"

  if [[ -z "$project_key" ]]; then
    project_key="$JIRA_PROJECT_KEY_LOCAL"
  fi

  local links_text=""
  if [[ "${#links[@]-0}" -gt 0 ]]; then
    local link_item
    for link_item in "${links[@]-}"; do
      if [[ -n "$links_text" ]]; then
        links_text+=$' '
      fi
      links_text+="$link_item"
    done
  fi
  context_text="$summary"$'\n'"$description"$'\n'"$reason"$'\n'"$links_text"

  if [[ -z "$reason" ]]; then
    reason="tarefa"
  fi

  issue_type="$(infer_issue_type "$reason $context_text")"
  local inferred_product inferred_integration inferred_category inferred_project_label inferred_component
  inferred_product="$(infer_product "$context_text")"
  inferred_integration="$(infer_integration "$context_text")"
  inferred_category="$(infer_category "$context_text")"
  inferred_project_label="$(infer_project_label "$context_text")"
  inferred_component="$(infer_component "$context_text $inferred_integration $inferred_project_label")"

  if [[ -z "$product" ]]; then
    learned_product="$(predict_field_from_learning "product" "$context_text" || true)"
    if ! is_not_applicable_value "$inferred_product"; then
      product="$inferred_product"
    elif [[ -n "$learned_product" ]]; then
      product="$learned_product"
    else
      product="$inferred_product"
    fi
  fi
  if [[ -z "$integration" ]]; then
    learned_integration="$(predict_field_from_learning "integration" "$context_text" || true)"
    if [[ -n "$inferred_integration" ]]; then
      integration="$inferred_integration"
    elif [[ -n "$learned_integration" ]]; then
      integration="$learned_integration"
    fi
  fi
  if [[ -z "$category" ]]; then
    learned_category="$(predict_field_from_learning "category" "$context_text" || true)"
    if ! is_not_applicable_value "$inferred_category"; then
      category="$inferred_category"
    elif [[ -n "$learned_category" ]]; then
      category="$learned_category"
    else
      category="$inferred_category"
    fi
  fi
  if [[ -z "$project_label" ]]; then
    if ! is_not_applicable_value "$inferred_project_label"; then
      project_label="$inferred_project_label"
    else
      project_label="$inferred_project_label"
    fi
  fi
  if [[ -z "$component" ]]; then
    learned_component="$(predict_field_from_learning "component" "$context_text" || true)"
    if ! is_not_applicable_value "$inferred_component"; then
      component="$inferred_component"
    elif [[ -n "$learned_component" ]]; then
      component="$learned_component"
    else
      component="$inferred_component"
    fi
  fi

  if [[ -n "$assignee_name" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      assignee_json="$(resolve_assignee_from_cache_only "$assignee_name" || true)"
    else
      assignee_json="$(resolve_assignee "$assignee_name" || true)"
    fi

    if [[ -n "$assignee_json" && "$assignee_json" != "{}" ]]; then
      assignee_account_id="$(jq -r '.accountId // empty' <<<"$assignee_json")"
      assignee_display_name="$(jq -r '.displayName // empty' <<<"$assignee_json")"
    fi
  fi

  if [[ "$dry_run" != "true" ]]; then
    if [[ "$force_sync_fields" == "true" ]]; then
      sync_field_ids
    else
      maybe_sync_field_ids
    fi
  fi

  product_field="$(jq -r '.fieldIds.product // empty' "$FIELD_CACHE")"
  integration_field="$(jq -r '.fieldIds.integration // empty' "$FIELD_CACHE")"
  category_field="$(jq -r '.fieldIds.category // empty' "$FIELD_CACHE")"
  project_label_field="$(jq -r '.fieldIds.projectLabel // empty' "$FIELD_CACHE")"
  component_field="components"
  if [[ -n "$product_field" ]]; then issue_fields_query+=",${product_field}"; fi
  if [[ -n "$integration_field" ]]; then issue_fields_query+=",${integration_field}"; fi
  if [[ -n "$category_field" ]]; then issue_fields_query+=",${category_field}"; fi
  if [[ -n "$project_label_field" ]]; then issue_fields_query+=",${project_label_field}"; fi

  if [[ "$dry_run" != "true" ]]; then
    createmeta_json="$(jira_get "rest/api/3/issue/createmeta?projectKeys=$(urlencode "$project_key")&expand=projects.issuetypes.fields" || echo '{}')"
  fi

  if [[ -n "$product_field" ]]; then
    product_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$product_field")"
    product_required="$(jq -r '.required // false' <<<"$product_spec")"
    product_allowed="$(jq -c '.allowed // []' <<<"$product_spec")"
    product_schema_type="$(jq -r '.schema.type // empty' <<<"$product_spec")"
    product_schema_items="$(jq -r '.schema.items // empty' <<<"$product_spec")"
    selected_product="$(pick_allowed_value "product" "$product" "$product_allowed" "$product_required")"
    if [[ -n "$selected_product" ]]; then
      case "${product_schema_type}:${product_schema_items}" in
        array:option)
          custom_fields_json="$(jq --arg field "$product_field" --arg value "$selected_product" '. + {($field): [{value: $value}]}' <<<"$custom_fields_json")"
          product="$selected_product"
          ;;
        option|"")
          custom_fields_json="$(jq --arg field "$product_field" --arg value "$selected_product" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
          product="$selected_product"
          ;;
        array:string)
          custom_fields_json="$(jq --arg field "$product_field" --arg value "$selected_product" '. + {($field): [$value]}' <<<"$custom_fields_json")"
          product="$selected_product"
          ;;
        string)
          custom_fields_json="$(jq --arg field "$product_field" --arg value "$selected_product" '. + {($field): $value}' <<<"$custom_fields_json")"
          product="$selected_product"
          ;;
      esac
    fi
  fi

  if [[ -n "$integration_field" ]]; then
    integration_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$integration_field")"
    integration_required="$(jq -r '.required // false' <<<"$integration_spec")"
    integration_allowed="$(jq -c '.allowed // []' <<<"$integration_spec")"
    integration_schema_type="$(jq -r '.schema.type // empty' <<<"$integration_spec")"
    integration_schema_items="$(jq -r '.schema.items // empty' <<<"$integration_spec")"
    selected_integration="$(pick_allowed_value "integration" "$integration" "$integration_allowed" "$integration_required")"
    if [[ -n "$selected_integration" ]]; then
      case "${integration_schema_type}:${integration_schema_items}" in
        array:option)
          custom_fields_json="$(jq --arg field "$integration_field" --arg value "$selected_integration" '. + {($field): [{value: $value}]}' <<<"$custom_fields_json")"
          integration="$selected_integration"
          ;;
        option|"")
          custom_fields_json="$(jq --arg field "$integration_field" --arg value "$selected_integration" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
          integration="$selected_integration"
          ;;
        array:string)
          custom_fields_json="$(jq --arg field "$integration_field" --arg value "$selected_integration" '. + {($field): [$value]}' <<<"$custom_fields_json")"
          integration="$selected_integration"
          ;;
        string)
          custom_fields_json="$(jq --arg field "$integration_field" --arg value "$selected_integration" '. + {($field): $value}' <<<"$custom_fields_json")"
          integration="$selected_integration"
          ;;
      esac
    fi
  fi

  if [[ -n "$category_field" ]]; then
    category_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$category_field")"
    category_required="$(jq -r '.required // false' <<<"$category_spec")"
    category_allowed="$(jq -c '.allowed // []' <<<"$category_spec")"
    category_schema_type="$(jq -r '.schema.type // empty' <<<"$category_spec")"
    category_schema_items="$(jq -r '.schema.items // empty' <<<"$category_spec")"
    selected_category="$(pick_allowed_value "category" "$category" "$category_allowed" "$category_required")"
    if [[ -n "$selected_category" ]]; then
      case "${category_schema_type}:${category_schema_items}" in
        array:option)
          custom_fields_json="$(jq --arg field "$category_field" --arg value "$selected_category" '. + {($field): [{value: $value}]}' <<<"$custom_fields_json")"
          category="$selected_category"
          ;;
        option|"")
          custom_fields_json="$(jq --arg field "$category_field" --arg value "$selected_category" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
          category="$selected_category"
          ;;
        array:string)
          custom_fields_json="$(jq --arg field "$category_field" --arg value "$selected_category" '. + {($field): [$value]}' <<<"$custom_fields_json")"
          category="$selected_category"
          ;;
        string)
          custom_fields_json="$(jq --arg field "$category_field" --arg value "$selected_category" '. + {($field): $value}' <<<"$custom_fields_json")"
          category="$selected_category"
          ;;
      esac
    fi
  fi

  if [[ -n "$project_label_field" ]]; then
    project_label_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$project_label_field")"
    project_label_required="$(jq -r '.required // false' <<<"$project_label_spec")"
    project_label_allowed="$(jq -c '.allowed // []' <<<"$project_label_spec")"
    project_label_schema_type="$(jq -r '.schema.type // empty' <<<"$project_label_spec")"
    project_label_schema_items="$(jq -r '.schema.items // empty' <<<"$project_label_spec")"
    selected_project_label="$(pick_allowed_value "projectLabel" "$project_label" "$project_label_allowed" "$project_label_required")"
    if [[ -n "$selected_project_label" ]]; then
      case "${project_label_schema_type}:${project_label_schema_items}" in
        array:option)
          custom_fields_json="$(jq --arg field "$project_label_field" --arg value "$selected_project_label" '. + {($field): [{value: $value}]}' <<<"$custom_fields_json")"
          project_label="$selected_project_label"
          ;;
        option|"")
          custom_fields_json="$(jq --arg field "$project_label_field" --arg value "$selected_project_label" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
          project_label="$selected_project_label"
          ;;
        array:string)
          custom_fields_json="$(jq --arg field "$project_label_field" --arg value "$selected_project_label" '. + {($field): [$value]}' <<<"$custom_fields_json")"
          project_label="$selected_project_label"
          ;;
        string)
          custom_fields_json="$(jq --arg field "$project_label_field" --arg value "$selected_project_label" '. + {($field): $value}' <<<"$custom_fields_json")"
          project_label="$selected_project_label"
          ;;
      esac
    fi
  fi

  if [[ -n "$component_field" ]]; then
    component_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$component_field")"
    component_required="$(jq -r '.required // false' <<<"$component_spec")"
    component_allowed="$(jq -c '.allowed // []' <<<"$component_spec")"
    selected_component="$(pick_allowed_value "component" "$component" "$component_allowed" "$component_required")"
    if [[ -n "$selected_component" ]]; then
      payload_component_json="$(jq -n --arg name "$selected_component" '[{name: $name}]')"
      component="$selected_component"
    fi
  fi

  description_text=""
  if [[ -n "$description" ]]; then
    description_text+="$description"
  fi

  if [[ "${#links[@]-0}" -gt 0 ]]; then
    if [[ -n "${description_text//[[:space:]]/}" ]]; then
      description_text+=$'\n\n'
    fi
    for link in "${links[@]-}"; do
      [[ -n "$link" ]] || continue
      description_text+="$link"$'\n'
    done
  fi

  if [[ "$append_classification_in_desc" == "true" || -z "${description//[[:space:]]/}" ]]; then
    if [[ -n "${description_text//[[:space:]]/}" ]]; then
      description_text+=$'\n\n'
    fi
    description_text+="## Classificacao aplicada automaticamente"$'\n'
    description_text+="- Motivo: ${reason}"$'\n'
    description_text+="- Tipo Jira: ${issue_type}"$'\n'
    description_text+="- Produto: ${product}"$'\n'
    description_text+="- Projeto: ${project_label}"$'\n'
    description_text+="- Integracao: ${integration:-N/A}"$'\n'
    description_text+="- Categoria: ${category}"$'\n'
    description_text+="- Prioridade: ${priority}"$'\n'
    if [[ -n "$assignee_display_name" ]]; then
      description_text+="- Assignee: ${assignee_display_name}"$'\n'
    elif [[ -n "$assignee_name" ]]; then
      description_text+="- Assignee solicitado: ${assignee_name}"$'\n'
    fi
  fi

  description_doc="$(build_adf_description "$description_text")"

  payload="$(jq -n \
    --arg projectKey "$project_key" \
    --arg summary "$summary" \
    --arg issueType "$issue_type" \
    --arg priority "$priority" \
    --arg accountId "$assignee_account_id" \
    --argjson desc "$description_doc" \
    '{
      fields: {
        project: {key: $projectKey},
        summary: $summary,
        issuetype: {name: $issueType},
        priority: {name: $priority},
        description: $desc
      }
    }
    | if $accountId != "" then .fields.assignee = {accountId: $accountId} else . end
  ')"

  payload="$(jq --argjson custom "$custom_fields_json" '.fields += $custom' <<<"$payload")"
  if [[ -n "$payload_component_json" ]]; then
    payload="$(jq --argjson comps "$payload_component_json" '.fields.components = $comps' <<<"$payload")"
  fi
  if [[ -n "$category" ]]; then
    category_label="$(to_label_slug "$category")"
    if [[ -n "$category_label" ]]; then
      labels_json="$(jq -n --arg lbl "categoria:$category_label" '[$lbl]')"
      payload="$(jq --argjson labels "$labels_json" '.fields.labels = (($labels + (.fields.labels // [])) | unique)' <<<"$payload")"
    fi
  fi

  if [[ "$dry_run" == "true" ]]; then
    jq -n \
      --arg summary "$summary" \
      --arg projectKey "$project_key" \
      --arg issueType "$issue_type" \
      --arg priority "$priority" \
      --arg assignee "$assignee_display_name" \
      --arg accountId "$assignee_account_id" \
      --arg product "$product" \
      --arg projectLabel "$project_label" \
      --arg integration "${integration:-}" \
      --arg category "$category" \
      --arg component "$component" \
      --argjson payload "$payload" \
      '{
        dryRun: true,
        classification: {
          summary: $summary,
          projectKey: $projectKey,
          issueType: $issueType,
          priority: $priority,
          assignee: $assignee,
          accountId: $accountId,
          product: $product,
          projectLabel: $projectLabel,
          integration: $integration,
          category: $category,
          component: $component
        },
        payload: $payload
      }'
    return 0
  fi

  issue_response="$(jira_post "rest/api/3/issue" "$payload")"
  issue_key="$(jq -r '.key // empty' <<<"$issue_response")"
  issue_id="$(jq -r '.id // empty' <<<"$issue_response")"

  [[ -n "$issue_key" ]] || die "Falha ao criar issue no Jira: resposta sem key"

  transitioned_to_todo="$(ensure_todo_status "$issue_key")"
  issue_fields_json="$(jira_get "rest/api/3/issue/${issue_key}?fields=$(urlencode "$issue_fields_query")" || echo '{}')"
  status_name="$(jq -r '.fields.status.name // empty' <<<"$issue_fields_json")"
  issue_url="${JIRA_BASE_URL}browse/${issue_key}"

  final_product="$product"
  final_project_label="$project_label"
  final_integration="$integration"
  final_category="$category"
  final_component="$component"

  if [[ -n "$product_field" ]]; then
    final_product="$(extract_issue_field_value "$issue_fields_json" "$product_field")"
    [[ -n "$final_product" ]] || final_product="$product"
  fi
  if [[ -n "$project_label_field" ]]; then
    final_project_label="$(extract_issue_field_value "$issue_fields_json" "$project_label_field")"
    [[ -n "$final_project_label" ]] || final_project_label="$project_label"
  fi
  if [[ -n "$integration_field" ]]; then
    final_integration="$(extract_issue_field_value "$issue_fields_json" "$integration_field")"
    [[ -n "$final_integration" ]] || final_integration="$integration"
  fi
  if [[ -n "$category_field" ]]; then
    final_category="$(extract_issue_field_value "$issue_fields_json" "$category_field")"
    [[ -n "$final_category" ]] || final_category="$category"
  fi
  final_component="$(extract_issue_field_value "$issue_fields_json" "components")"
  [[ -n "$final_component" ]] || final_component="$component"

  learn_classification_set \
    "$context_text" \
    "$final_product" \
    "$final_project_label" \
    "$final_integration" \
    "$final_category" \
    "$final_component"

  jq -n \
    --arg issueKey "$issue_key" \
    --arg issueId "$issue_id" \
    --arg issueUrl "$issue_url" \
    --arg status "$status_name" \
    --arg transitioned "$transitioned_to_todo" \
    --arg projectKey "$project_key" \
    --arg issueType "$issue_type" \
    --arg priority "$priority" \
    --arg assigneeName "$assignee_display_name" \
    --arg assigneeAccountId "$assignee_account_id" \
    --arg product "$final_product" \
    --arg projectLabel "$final_project_label" \
    --arg integration "${final_integration:-}" \
    --arg category "$final_category" \
    --arg component "$final_component" \
    '{
      ok: true,
      issue: {
        key: $issueKey,
        id: $issueId,
        url: $issueUrl,
        status: $status
      },
      classification: {
        projectKey: $projectKey,
        issueType: $issueType,
        priority: $priority,
        assigneeName: $assigneeName,
        assigneeAccountId: $assigneeAccountId,
        product: $product,
        projectLabel: $projectLabel,
        integration: $integration,
        category: $category,
        component: $component
      },
      transitionedToPending: ($transitioned == "true")
    }'
}

print_help() {
  cat <<'EOF'
Uso:
  jira-helper.sh assignee-resolve "Nome"
  jira-helper.sh assignee-list
  jira-helper.sh sync-fields
  jira-helper.sh learning-report
  jira-helper.sh learn-from-issue --issue-key "SME-123" [--context "..."]
  jira-helper.sh classify --summary "..." [opcoes]
  jira-helper.sh create --summary "..." [opcoes]

Comando create:
  --summary "Titulo da tarefa"                (obrigatorio)
  --description "Descricao detalhada"
  --assignee "Nome da pessoa"
  --reason "bug|melhoria|tarefa|..."
  --product "APP|Portal|API|..."
  --project-label "SME project|..."
  --integration "DHL|Correios|..."
  --category "Tracking|Operacao|..."
  --priority "Highest|High|..."
  --project-key "SME"
  --link "https://..."
  --sync-fields                                (forca refresh do cache de campos)
  --dry-run                                    (gera payload sem criar issue)
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    assignee-resolve)
      cmd_assignee_resolve "$@"
      ;;
    assignee-list)
      cmd_assignee_list
      ;;
    sync-fields)
      cmd_sync_fields
      ;;
    learning-report)
      cmd_learning_report
      ;;
    learn-from-issue)
      cmd_learn_from_issue "$@"
      ;;
    classify)
      cmd_classify "$@"
      ;;
    create)
      cmd_create "$@"
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      print_help
      die "Comando invalido: $cmd"
      ;;
  esac
}

main "$@"
