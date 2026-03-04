#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../..\" && pwd)"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${HOME}/.openclaw}"
RUNTIME_GUARD="${SCRIPT_DIR}/runtime-guard.sh"
TMP_DIR="${PROJECT_ROOT}/workspace/tmp"
LAST_HASH_FILE="${TMP_DIR}/main-hourly-last.hash"
MAIN_HOURLY_DEDUP_ENABLED="${MAIN_HOURLY_DEDUP_ENABLED:-true}"

DB_SMARTENVIOS_ID="adec12e735dc41a3bb7c274b287f3a10"
DB_PERSONAL_ID="bfcbe7a7a3a745489e605e0762af12a9"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  set +e
  set +u
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env" >/dev/null 2>&1
  set -u
  set -e
fi

# Not sure if NOTION_SMARTENVIOS_API_KEY / NOTION_PERSONAL_API_KEY are loaded by default
# Ensure they are available
NOTION_SMARTENVIOS_API_KEY="${NOTION_SMARTENVIOS_API_KEY:-}"
NOTION_PERSONAL_API_KEY="${NOTION_PERSONAL_API_KEY:-}"

if [[ -x "${RUNTIME_GUARD}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_GUARD}"
  if ! ocw_guard_acquire_lock "main-hourly-whatsapp-report" "${CRON_LOCK_STALE_SEC:-1800}"; then
    echo '{"ok":true,"action":"skipped_already_running","lock":"main-hourly-whatsapp-report"}'
    exit 0
  fi
  ocw_guard_mark_start
  trap 'ocw_guard_release_lock' EXIT
fi

run_with_timeout() {
  local timeout_sec="$1"
  shift
  python3 - "$timeout_sec" "$@" <<'PY'
import subprocess
import sys

timeout_sec = float(sys.argv[1])
cmd = sys.argv[2:]
if not cmd:
    sys.exit(2)
try:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_sec)
    if proc.stdout:
        sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    sys.exit(proc.returncode)
except subprocess.TimeoutExpired:
    sys.stderr.write("timeout\n")
    sys.exit(124)
PY
}

resolve_whatsapp_target() {
  if [[ -n "${OPENCLAW_MAIN_WHATSAPP_TARGET:-}" ]]; then
    echo "${OPENCLAW_MAIN_WHATSAPP_TARGET}"
    return
  fi
  if [[ -n "${OPENCLAW_GOV_WHATSAPP_TARGET:-}" ]]; then
    echo "${OPENCLAW_GOV_WHATSAPP_TARGET}"
    return
  fi

  local config_path="${PROJECT_ROOT}/openclaw.json"
  [[ -f "${config_path}" ]] || return
  python3 - "${config_path}" <<'PY'
import json
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
try:
    data = json.loads(cfg.read_text(encoding="utf-8"))
except Exception:
    print("")
    raise SystemExit

candidates = (((data.get("channels") or {}).get("whatsapp") or {}).get("allowFrom") or [])
for raw in candidates:
    if not isinstance(raw, str):
        continue
    cleaned = raw.strip()
    if re.match(r"^\\+\\d{8,16}$", cleaned):
        print(cleaned)
        raise SystemExit

print("")
PY
}

notion_helper_query() {
  local db_id="$1"
  local api_key_var="$2"
  local agent_filter="${3:-.*}" # Default to match all agents
  local status1="${4:-Priorizado}"
  local status2="${5:-Em andamento}" # This is likely not used for 'all' query but kept for compatibility
  
  local notion_output
  notion_output=$(run_with_timeout 30 "${SCRIPT_DIR}/notion-helper.sh" query "$db_id" "$api_key_var" "$agent_filter" "$status1" "$status2" 2>/dev/null || true)
  
  if echo "$notion_output" | jq -e 'has("error")' > /dev/null; then
    echo "Erro ao consultar Notion (DB: $db_id): $(echo "$notion_output" | jq -r '.error')" >&2
    echo ""
  else
    echo "$notion_output"
  fi
}

get_notion_card_activity() {
  local db_id="$1"
  local api_key_var="$2"
  local db_name="$3"
  local report_output=""
  
  local all_cards_json
  all_cards_json=$(notion_helper_query "$db_id" "$api_key_var" ".*" "" "") # Query all cards, all statuses

  if [[ -z "$all_cards_json" ]]; then
    echo ""
    return 0
  fi

  local NOW_MS=$(date +%s%3N)
  local ONE_HOUR_AGO_MS=$((NOW_MS - 3600000)) # 1 hour in milliseconds
  
  local created_cards_json
  created_cards_json=$(echo "$all_cards_json" | jq -r --argjson one_hour_ago_ms "$ONE_HOUR_AGO_MS" '\
    .results[] | select(\
      (.created_time | fromdateiso8601) >= ($one_hour_ago_ms / 1000)\
    ) | {\
      title: .properties.Name.title[0].plain_text, \
      status: .properties.Status.select.name, \
      created_time: .created_time,\
      url: .url\
    }' | jq -s '.')

  local completed_cards_json
  completed_cards_json=$(echo "$all_cards_json" | jq -r --argjson one_hour_ago_ms "$ONE_HOUR_AGO_MS" '\
    .results[] | select(\
      (.last_edited_time | fromdateiso8601) >= ($one_hour_ago_ms / 1000) and \
      .properties.Status.select.name == "Concluído"\
    ) | {\
      title: .properties.Name.title[0].plain_text, \
      status: .properties.Status.select.name, \
      last_edited_time: .last_edited_time,\
      url: .url\
    }' | jq -s '.')

  if [[ $(echo "$created_cards_json" | jq length) -gt 0 ]]; then
    report_output+="* Novos Cards em $db_name: *\\n"
    while IFS= read -r card; do
      title=$(echo "$card" | jq -r '.title')
      status=$(echo "$card" | jq -r '.status')
      url=$(echo "$card" | jq -r '.url')
      report_output+="- [$title]($url) (Status: $status)\\n"
    done < <(echo "$created_cards_json" | jq -c '.[]')
    report_output+="\\n"
  fi

  if [[ $(echo "$completed_cards_json" | jq length) -gt 0 ]]; then
    report_output+="* Cards Concluídos em $db_name na última hora: *\\n"
    while IFS= read -r card; do
      title=$(echo "$card" | jq -r '.title')
      url=$(echo "$card" | jq -r '.url')
      report_output+="- [$title]($url)\\n"
    done < <(echo "$completed_cards_json" | jq -c '.[]')
    report_output+="\\n"
  fi
  
  echo -e "$report_output"
}


target="$(resolve_whatsapp_target)"
if [[ -z "${target:-}" ]]; then
  echo '{"ok":false,"error":"whatsapp target not configured"}'
  exit 1
fi

CRON_JSON="$(run_with_timeout 20 openclaw cron list --json 2>/dev/null || true)"
if [[ -z "${CRON_JSON//[[:space:]]/}" ]] && [[ -f "${OPENCLAW_CONFIG_DIR}/cron/jobs.json" ]]; then
  CRON_JSON="$(cat "${OPENCLAW_CONFIG_DIR}/cron/jobs.json" 2>/dev/null || true)"
fi
if [[ -z "${CRON_JSON//[[:space:]]/}" ]]; then
  CRON_JSON='{"jobs":[]}'
fi

tmp_json="$(mktemp "/tmp/main-hourly-cron-XXXXXX.json")"
printf '%s' "${CRON_JSON}" > "${tmp_json}"

NOTION_ACTIVITY_SMARTENVIOS="$(get_notion_card_activity "$DB_SMARTENVIOS_ID" "NOTION_SMARTENVIOS_API_KEY" "SmartEnvios")"
NOTION_ACTIVITY_PERSONAL="$(get_notion_card_activity "$DB_PERSONAL_ID" "NOTION_PERSONAL_API_KEY" "Pessoal")"

message="$(python3 - "${tmp_json}" "${NOTION_ACTIVITY_SMARTENVIOS}" "${NOTION_ACTIVITY_PERSONAL}" <<\'PY\'
import datetime
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {"jobs": []}

notion_activity_smartenvios = sys.argv[2]
notion_activity_personal = sys.argv[3]

jobs = data.get("jobs", []) if isinstance(data, dict) else []
now_ms = int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000)
local_tz = datetime.datetime.now().astimezone().tzinfo
now_str = datetime.datetime.now(local_tz).strftime("%d/%m/%Y %H:%M")

def last_state(job):
    st = job.get("state") or {}
    running_at = int(st.get("runningAtMs") or 0)
    if running_at > 0:
        return "rodando"
    status = str(st.get("lastRunStatus") or st.get("lastStatus") or "idle").lower()
    if status in {"error", "failed", "timeout"}:
        return "erro"
    return "ok" if status == "ok" else status

enabled = [j for j in jobs if j.get("enabled", True)]
ok = 0
err = 0
running = 0
for j in enabled:
    s = last_state(j)
    if s == "ok":
        ok += 1
    elif s == "rodando":
        running += 1
    elif s == "erro":
        err += 1

latest = sorted(
    enabled,
    key=lambda x: int(((x.get("state") or {}).get("lastRunAtMs") or 0)),
    reverse=True
)[:5]

def fmt_last(job):
    ms = int(((job.get("state") or {}).get("lastRunAtMs") or 0))
    if ms <= 0:
        return "-"
    dt = datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).astimezone(local_tz)
    return dt.strftime("%H:%M")

lines = []
lines.append(f"Main | Relatorio horario")
lines.append(f"Horario: {now_str}")
lines.append(f"Crons ativos: {len(enabled)}/{len(jobs)} | ok={ok} rodando={running} erro={err}")

if notion_activity_smartenvios or notion_activity_personal:
  lines.append(f"\\n* Atividade Notion na Ultima Hora *\\n")
  if notion_activity_smartenvios:
    lines.append(notion_activity_smartenvios.strip())
  if notion_activity_personal:
    lines.append(notion_activity_personal.strip())
else:
  lines.append(f"\\n* Nenhuma atividade de cards no Notion na ultima hora. *\\n")

lines.append("\\nUltimas execucoes:")
for j in latest:
    name = str(j.get("name") or "?")
    state = last_state(j)
    lines.append(f"- {name[:46]} | {state} | {fmt_last(j)}")

print("\\n".join(lines)[:3500])
PY
)"
rm -f "${tmp_json}" >/dev/null 2>&1 || true

mkdir -p "${TMP_DIR}" >/dev/null 2>&1 || true
msg_hash="$(printf '%s' "${message}" | shasum -a 256 | awk '{print $1}')"
if [[ "${MAIN_HOURLY_DEDUP_ENABLED}" == "true" ]] && [[ -f "${LAST_HASH_FILE}" ]]; then
  prev_hash="$(cat "${LAST_HASH_FILE}" 2>/dev/null || true)"
  if [[ -n "${prev_hash}" ]] && [[ "${prev_hash}" == "${msg_hash}" ]]; then
    if type ocw_guard_mark_end >/dev/null 2>&1; then
      elapsed="$(ocw_guard_mark_end)"
      echo "{\"ok\":true,\"action\":\"skipped_no_change\",\"runtimeSec\":${elapsed}}"
    else
      echo '{"ok":true,"action":"skipped_no_change"}'
    fi
    exit 0
  fi
fi

run_with_timeout 20 openclaw message send --channel whatsapp --target "${target}" --message "${message}" >/dev/null
printf '%s\\n' "${msg_hash}" > "${LAST_HASH_FILE}" 2>/dev/null || true
if type ocw_guard_mark_end >/dev/null 2>&1; then
  elapsed="$(ocw_guard_mark_end)"
  echo "{\"ok\":true,\"sentBy\":\"main-hourly-report\",\"runtimeSec\":${elapsed}}"
else
  echo '{"ok":true,"sentBy\":\"main-hourly-report"}'
fi
