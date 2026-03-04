#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${SCRIPT_DIR}/notion-helper.sh"
GMAIL="${ROOT_DIR}/scripts/gmail/gmail.sh"
OPENCLAW_HELPER="${SCRIPT_DIR}/openclaw-helper.sh"
RUNTIME_GUARD="${SCRIPT_DIR}/runtime-guard.sh"

if [[ -f "${ROOT_DIR}/../.env" ]]; then
  set +e +u
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/../.env" >/dev/null 2>&1
  set -euo pipefail
fi

if [[ -x "${RUNTIME_GUARD}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_GUARD}"
  if ! ocw_guard_acquire_lock "president-mail-demand-cycle" "${CRON_LOCK_STALE_SEC:-1200}"; then
    echo '{"ok":true,"action":"skipped_already_running","lock":"president-mail-demand-cycle"}'
    exit 0
  fi
  trap 'ocw_guard_release_lock' EXIT
fi

if [[ ! -x "${HELPER}" || ! -x "${GMAIL}" ]]; then
  echo '{"ok":false,"error":"required_scripts_missing"}'
  exit 2
fi

TECH_DB="adec12e735dc41a3bb7c274b287f3a10"
PERSONAL_DB="bfcbe7a7a3a745489e605e0762af12a9"
CREATE_THRESHOLD_PRO="${MAIL_BACKLOG_CREATE_THRESHOLD_PRO:-1}"
CREATE_THRESHOLD_PERSONAL="${MAIL_BACKLOG_CREATE_THRESHOLD_PERSONAL:-1}"
COOLDOWN_SEC="${MAIL_BACKLOG_CREATE_COOLDOWN_SEC:-3600}"
STATE_FILE="/tmp/openclaw-president-mail-demand-state.json"
FORCE_FILE="/tmp/openclaw-president-force-governance.json"
FORCE_WAKE_STATE_FILE="/tmp/openclaw-president-force-wake-state.json"
FORCE_WAKE_COOLDOWN_SEC="${PRESIDENT_FORCE_WAKE_COOLDOWN_SEC:-600}"
PRESIDENT_DIRECT_WAKE_ENABLED="${PRESIDENT_DIRECT_WAKE_ENABLED:-false}"
FORCE_CHAIN_THRESHOLD_PRO="${PRESIDENT_FORCE_CHAIN_THRESHOLD_PRO:-20}"
FORCE_CHAIN_THRESHOLD_PERSONAL="${PRESIDENT_FORCE_CHAIN_THRESHOLD_PERSONAL:-5}"
FORCE_CHAIN_ENABLED="${PRESIDENT_FORCE_CHAIN_ENABLED:-true}"
CREATE_WHEN_CHAIN_EMPTY="${MAIL_BACKLOG_CREATE_WHEN_CHAIN_EMPTY:-true}"
GOVERNANCE_CRON_ID="${GOVERNANCE_CRON_ID:-}"
DIRECTOR_TECH_CRON="7fba5b1f-2ee9-4b1e-aae0-bd211c32b925"
DIRECTOR_PERSONAL_CRON="a71c2958-e52f-4f37-9876-bedf6dcb9434"
MAIL_PRO_CRON="99de71d1-97b0-48d0-933e-7fcacfda2184"
MAIL_PERSON_CRON="e4cd9635-efdd-4588-8ecc-523a4a50ea20"
OPTIMIZER_CRON="59c24991-af6c-4df2-95fe-bbf012cd73c0"
PRESIDENT_AUTONOMOUS_MIGRATION_ENABLED="${PRESIDENT_AUTONOMOUS_MIGRATION_ENABLED:-true}"
PRESIDENT_MIGRATION_TITLE_PREFIX="${PRESIDENT_MIGRATION_TITLE_PREFIX:-[Presidente][N8N] Cobertura migração OLD->NEW}"
PRESIDENT_INCLUDE_EXEC_INSIGHTS="${PRESIDENT_INCLUDE_EXEC_INSIGHTS:-true}"
PRESIDENT_EXEC_INSIGHTS_HOURS="${PRESIDENT_EXEC_INSIGHTS_HOURS:-6}"

[[ ! "${CREATE_THRESHOLD_PRO}" =~ ^[0-9]+$ ]] && CREATE_THRESHOLD_PRO=1
[[ ! "${CREATE_THRESHOLD_PERSONAL}" =~ ^[0-9]+$ ]] && CREATE_THRESHOLD_PERSONAL=1
[[ ! "${COOLDOWN_SEC}" =~ ^[0-9]+$ ]] && COOLDOWN_SEC=3600
[[ ! "${FORCE_CHAIN_THRESHOLD_PRO}" =~ ^[0-9]+$ ]] && FORCE_CHAIN_THRESHOLD_PRO=20
[[ ! "${FORCE_CHAIN_THRESHOLD_PERSONAL}" =~ ^[0-9]+$ ]] && FORCE_CHAIN_THRESHOLD_PERSONAL=5
[[ ! "${FORCE_WAKE_COOLDOWN_SEC}" =~ ^[0-9]+$ ]] && FORCE_WAKE_COOLDOWN_SEC=600
[[ ! "${PRESIDENT_EXEC_INSIGHTS_HOURS}" =~ ^[0-9]+$ ]] && PRESIDENT_EXEC_INSIGHTS_HOURS=6

force_chain_triggered=0
forced_crons='[]'
migration_audit='{"ok":false,"enabled":false}'
migration_card_action="none"
migration_card_id=""

if [[ -f "${OPENCLAW_HELPER}" ]]; then
  # shellcheck disable=SC1091
  source "${OPENCLAW_HELPER}" 2>/dev/null || true
fi

unread_pro_file="/tmp/president-unread-pro-$$.txt"
unread_personal_file="/tmp/president-unread-personal-$$.txt"
"${GMAIL}" pro list "is:unread in:inbox" 1 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null >"${unread_pro_file}" &
pid_unread_pro=$!
"${GMAIL}" personal list "is:unread in:inbox" 1 2>/dev/null | jq -r '.resultSizeEstimate // 0' 2>/dev/null >"${unread_personal_file}" &
pid_unread_personal=$!
wait "${pid_unread_pro}" "${pid_unread_personal}" 2>/dev/null || true
unread_pro="$(cat "${unread_pro_file}" 2>/dev/null || echo 0)"
unread_personal="$(cat "${unread_personal_file}" 2>/dev/null || echo 0)"
rm -f "${unread_pro_file}" "${unread_personal_file}" 2>/dev/null || true
[[ ! "${unread_pro}" =~ ^[0-9]+$ ]] && unread_pro=0
[[ ! "${unread_personal}" =~ ^[0-9]+$ ]] && unread_personal=0

query_agent_open() {
  local db_id="$1"
  local api_var="$2"
  local agent="$3"
  local q1 q2
  q1="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
  q2="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"
  jq -n --argjson a "${q1}" --argjson b "${q2}" '
    ((($a.results // []) + ($b.results // [])) | map(.id) | unique | length)
  '
}

query_agent_open_pages() {
  local db_id="$1"
  local api_var="$2"
  local agent="$3"
  local q1 q2
  q1="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
  q2="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"
  jq -n --argjson a "${q1}" --argjson b "${q2}" '
    ((($a.results // []) + ($b.results // [])) | unique_by(.id))
  '
}

query_agent_pages_with_impediment() {
  local db_id="$1"
  local api_var="$2"
  local agent="$3"
  local q1 q2 q3
  q1="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Aguardando" "Priorizado" 2>/dev/null || echo '{"results":[]}')"
  q2="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Em andamento" "Em andamento" 2>/dev/null || echo '{"results":[]}')"
  q3="$(NOTION_CACHE_ENABLED=true "${HELPER}" query "${db_id}" "${api_var}" "${agent}" "Impedimento" "Impedimento" 2>/dev/null || echo '{"results":[]}')"
  jq -n --argjson a "${q1}" --argjson b "${q2}" --argjson c "${q3}" '
    ((($a.results // []) + ($b.results // []) + ($c.results // [])) | unique_by(.id))
  '
}

find_existing_chain_card_by_prefix() {
  local db_id="$1"
  local api_var="$2"
  local prefix="$3"
  local combined='[]'
  local agents=()

  if [[ "${db_id}" == "${TECH_DB}" ]]; then
    agents=("Presidente" "Diretor Tech" "Engenheiro de Automação" "Engenheiro SmartEnvios" "Mail-Pro")
  else
    agents=("Presidente" "Diretor Pessoal" "Engenheiro de Prompt" "Mail-Person")
  fi

  local agent q
  for agent in "${agents[@]}"; do
    q="$(query_agent_pages_with_impediment "${db_id}" "${api_var}" "${agent}" 2>/dev/null || echo '[]')"
    combined="$(jq -cn --argjson cur "${combined}" --argjson add "${q}" '$cur + $add')"
  done

  jq -r --arg pref "${prefix}" '
    map(select(((.properties.Name.title[0].plain_text // "") | startswith($pref))))
    | unique_by(.id)
    | sort_by(.created_time // "9999-12-31T23:59:59.000Z")
    | .[0].id // ""
  ' <<<"${combined}" 2>/dev/null || true
}

count_chain_open_by_title_prefix() {
  local db_id="$1"
  local api_var="$2"
  local title_prefix="$3"
  local q_dir q_pres q_spec

  # Evita duplicação contando apenas cards da cadeia principal com o mesmo prefixo de título.
  if [[ "${db_id}" == "${TECH_DB}" ]]; then
    q_dir="$(query_agent_open_pages "${db_id}" "${api_var}" "Diretor Tech" 2>/dev/null || echo '[]')"
    q_pres="$(query_agent_open_pages "${db_id}" "${api_var}" "Presidente" 2>/dev/null || echo '[]')"
    q_spec="$(query_agent_open_pages "${db_id}" "${api_var}" "Mail-Pro" 2>/dev/null || echo '[]')"
  else
    q_dir="$(query_agent_open_pages "${db_id}" "${api_var}" "Diretor Pessoal" 2>/dev/null || echo '[]')"
    q_pres="$(query_agent_open_pages "${db_id}" "${api_var}" "Presidente" 2>/dev/null || echo '[]')"
    q_spec="$(query_agent_open_pages "${db_id}" "${api_var}" "Mail-Person" 2>/dev/null || echo '[]')"
  fi

  jq -n --argjson d "${q_dir:-[]}" --argjson p "${q_pres:-[]}" --argjson s "${q_spec:-[]}" --arg pref "${title_prefix}" '
    (($d + $p + $s)
      | map(select(((.properties.Name.title[0].plain_text // "") | startswith($pref))))
      | map(.id)
      | unique
      | length)
  '
}

can_create_with_cooldown() {
  local key="$1"
  local now last_created
  now="$(date +%s)"
  last_created=0
  if [[ -f "${STATE_FILE}" ]]; then
    last_created="$(jq -r --arg k "${key}" '.[$k] // 0' "${STATE_FILE}" 2>/dev/null || echo 0)"
  fi
  [[ ! "${last_created}" =~ ^[0-9]+$ ]] && last_created=0
  if (( now - last_created < COOLDOWN_SEC )); then
    return 1
  fi
  return 0
}

mark_created_now() {
  local key="$1"
  local now tmp
  now="$(date +%s)"
  tmp="${STATE_FILE}.tmp"
  if [[ -f "${STATE_FILE}" ]]; then
    jq --arg k "${key}" --argjson now "${now}" '.[$k]=$now' "${STATE_FILE}" > "${tmp}" 2>/dev/null || jq -n --arg k "${key}" --argjson now "${now}" '{($k):$now}' > "${tmp}"
  else
    jq -n --arg k "${key}" --argjson now "${now}" '{($k):$now}' > "${tmp}"
  fi
  mv "${tmp}" "${STATE_FILE}" 2>/dev/null || true
}

can_force_wake_now() {
  local now last
  now="$(date +%s)"
  last=0
  if [[ -f "${FORCE_WAKE_STATE_FILE}" ]]; then
    last="$(jq -r '.last // 0' "${FORCE_WAKE_STATE_FILE}" 2>/dev/null || echo 0)"
  fi
  [[ ! "${last}" =~ ^[0-9]+$ ]] && last=0
  (( now - last >= FORCE_WAKE_COOLDOWN_SEC ))
}

mark_force_wake_now() {
  local now tmp
  now="$(date +%s)"
  tmp="${FORCE_WAKE_STATE_FILE}.tmp"
  jq -n --argjson last "${now}" '{last:$last}' > "${tmp}" 2>/dev/null && mv "${tmp}" "${FORCE_WAKE_STATE_FILE}" 2>/dev/null || true
}

force_cron_once() {
  local cron_id="$1"
  [[ -z "${cron_id:-}" ]] && return 0
  if command -v ocw_cron_wake_now >/dev/null 2>&1; then
    if ocw_cron_wake_now "${cron_id}" 6000 >/dev/null 2>&1 || ocw_cron_run "${cron_id}" 6000 >/dev/null 2>&1; then
      forced_crons="$(jq -cn --argjson arr "${forced_crons}" --arg id "${cron_id}" '$arr + [$id]')"
      return 0
    fi
  fi
  if openclaw cron edit "${cron_id}" --wake now --timeout 6000 >/dev/null 2>&1 || openclaw cron run "${cron_id}" --timeout 6000 >/dev/null 2>&1; then
    forced_crons="$(jq -cn --argjson arr "${forced_crons}" --arg id "${cron_id}" '$arr + [$id]')"
    return 0
  fi
  return 1
}

run_n8n_migration_audit() {
  python3 - <<'PY'
import json, os, urllib.request
from collections import Counter

def fetch_all(base_url, key):
    out = []
    cursor = None
    while True:
        url = f"{base_url}/workflows?limit=250"
        if cursor:
            url = f"{url}&cursor={cursor}"
        req = urllib.request.Request(url, headers={"X-N8N-API-KEY": key})
        with urllib.request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        out.extend(data.get("data", []))
        cursor = data.get("nextCursor")
        if not cursor:
            break
    return out


enabled = (os.getenv("PRESIDENT_AUTONOMOUS_MIGRATION_ENABLED", "true").strip().lower() == "true")
if not enabled:
    print(json.dumps({"ok": False, "enabled": False, "reason": "disabled"}))
    raise SystemExit(0)

old_url = (os.getenv("OLD_N8N_URL", "").strip().rstrip("/"))
old_key = os.getenv("OLD_N8N_API_KEY", "").strip()
new_base = (os.getenv("N8N_API_BASE_URL", "https://n8n.smartenvios.tec.br/api/v1").strip().rstrip("/"))
sales_key = os.getenv("N8N_SALES_API_KEY", "").strip()
product_key = os.getenv("N8N_PRODUCT_API_KEY", "").strip()
finance_key = os.getenv("N8N_FINANCE_API_KEY", "").strip()
sucess_client_key = os.getenv("N8N_SUCESS_CLIENT_API_KEY", "").strip()
support_key = os.getenv("N8N_SUPPORT_API_KEY", "").strip()
engineering_key = os.getenv("N8N_ENGINEERING_API_KEY", "").strip()
marketing_key = os.getenv("N8N_MARKETING_API_KEY", "").strip()

missing_env = []
if not old_url: missing_env.append("OLD_N8N_URL")
if not old_key: missing_env.append("OLD_N8N_API_KEY")
if not sales_key: missing_env.append("N8N_SALES_API_KEY")
if not product_key: missing_env.append("N8N_PRODUCT_API_KEY")
if not finance_key: missing_env.append("N8N_FINANCE_API_KEY")
if not sucess_client_key: missing_env.append("N8N_SUCESS_CLIENT_API_KEY")
if not support_key: missing_env.append("N8N_SUPPORT_API_KEY")
if not engineering_key: missing_env.append("N8N_ENGINEERING_API_KEY")
if not marketing_key: missing_env.append("N8N_MARKETING_API_KEY")

if missing_env:
    print(json.dumps({
        "ok": False,
        "enabled": True,
        "reason": "missing_env",
        "missing_env": missing_env
    }))
    raise SystemExit(0)

try:
    old = fetch_all(f"{old_url}/api/v1", old_key)
    sales = fetch_all(new_base, sales_key)
    product = fetch_all(new_base, product_key)
    finance = fetch_all(new_base, finance_key)
    sucess_client = fetch_all(new_base, sucess_client_key)
    support = fetch_all(new_base, support_key)
    engineering = fetch_all(new_base, engineering_key)
    marketing = fetch_all(new_base, marketing_key)

    old_names = [(w.get("name") or "").strip() for w in old if (w.get("name") or "").strip()]
    new_names = []
    for arr in (sales, product, finance, sucess_client, support, engineering, marketing):
        for w in arr:
            n = (w.get("name") or "").strip()
            if n:
                new_names.append(n)

    old_cnt = Counter(old_names)
    new_cnt = Counter(new_names)
    missing = sorted([n for n, c in old_cnt.items() if new_cnt.get(n, 0) < c])
    duplicate_in_new = sorted([n for n, c in new_cnt.items() if c > old_cnt.get(n, 0)])
    print(json.dumps({
        "ok": True,
        "enabled": True,
        "old_count": len(old),
        "new_counts": {
            "sales": len(sales),
            "product": len(product),
            "finance": len(finance),
            "sucess_client": len(sucess_client),
            "support": len(support),
            "engineering": len(engineering),
            "marketing": len(marketing),
        },
        "missing_count": len(missing),
        "missing_names": missing[:50],
        "duplicate_excess_count": len(duplicate_in_new),
        "duplicate_excess_names": duplicate_in_new[:50]
    }))
except Exception as e:
    print(json.dumps({
        "ok": False,
        "enabled": True,
        "reason": "exception",
        "error": str(e)[:300]
    }))
PY
}

run_execution_insights() {
  python3 - "${ROOT_DIR}" "${PRESIDENT_INCLUDE_EXEC_INSIGHTS}" "${PRESIDENT_EXEC_INSIGHTS_HOURS}" <<'PY'
import glob
import json
import os
import time
import re
import sys

root = sys.argv[1]
enabled = (sys.argv[2].strip().lower() == "true")
hours = int(sys.argv[3]) if sys.argv[3].isdigit() else 6
hours = max(1, min(hours, 72))
if not enabled:
    print(json.dumps({"ok": False, "enabled": False, "reason": "disabled"}))
    raise SystemExit(0)

repo_root = os.path.abspath(os.path.join(root, ".."))
runs_dir = os.path.join(repo_root, "cron", "runs")
jobs_file = os.path.join(repo_root, "cron", "jobs.json")
now = int(time.time())
cutoff = now - (hours * 3600)

jobs = []
if os.path.exists(jobs_file):
    try:
        with open(jobs_file, "r", encoding="utf-8") as f:
            jobs = (json.load(f) or {}).get("jobs", [])
    except Exception:
        jobs = []

job_by_id = {}
for j in jobs:
    jid = str(j.get("id", "")).strip()
    if jid:
        job_by_id[jid] = {
            "id": jid,
            "name": j.get("name") or jid,
            "enabled": bool(j.get("enabled", True)),
            "lastRunAtMs": int(((j.get("state") or {}).get("lastRunAtMs") or 0)),
            "consecutiveErrors": int(((j.get("state") or {}).get("consecutiveErrors") or 0)),
            "lastStatus": (j.get("state") or {}).get("lastStatus") or (j.get("state") or {}).get("lastRunStatus") or "unknown",
        }

err_pat = re.compile(r"(isError=true|gateway timeout|rate limit|timeout|cron announce delivery failed)", re.IGNORECASE)

stats = {}
files_scanned = 0
for path in glob.glob(os.path.join(runs_dir, "*.jsonl")):
    try:
        mtime = int(os.path.getmtime(path))
    except Exception:
        continue
    if mtime < cutoff:
        continue
    files_scanned += 1
    job_id = os.path.basename(path).replace(".jsonl", "")
    st = stats.setdefault(job_id, {"entries": 0, "errorHits": 0, "recentTs": 0})
    st["recentTs"] = max(st["recentTs"], mtime)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()[-300:]
    except Exception:
        continue
    for line in lines:
        st["entries"] += 1
        if err_pat.search(line):
            st["errorHits"] += 1

focus = []
for jid, st in stats.items():
    jb = job_by_id.get(jid, {"id": jid, "name": jid, "enabled": True, "lastRunAtMs": 0, "consecutiveErrors": 0, "lastStatus": "unknown"})
    focus.append({
        "id": jid,
        "name": jb["name"],
        "errorHits": st["errorHits"],
        "entries": st["entries"],
        "recentRunAgeSec": max(0, now - st["recentTs"]) if st["recentTs"] else None,
        "consecutiveErrors": jb["consecutiveErrors"],
        "lastStatus": jb["lastStatus"],
    })

focus.sort(key=lambda x: (x["errorHits"], x["consecutiveErrors"]), reverse=True)
top = [x for x in focus if (x["errorHits"] > 0 or x["consecutiveErrors"] > 0)][:8]

stale = []
for jb in job_by_id.values():
    if not jb["enabled"]:
        continue
    age_sec = None
    if jb["lastRunAtMs"] > 0:
        age_sec = max(0, now - int(jb["lastRunAtMs"] / 1000))
    if age_sec is None or age_sec > 7200:
        stale.append({"id": jb["id"], "name": jb["name"], "ageSec": age_sec, "lastStatus": jb["lastStatus"]})

stale.sort(key=lambda x: (x["ageSec"] is None, x["ageSec"] or 10**9), reverse=True)

print(json.dumps({
    "ok": True,
    "enabled": True,
    "windowHours": hours,
    "filesScanned": files_scanned,
    "topIssues": top,
    "staleJobs": stale[:8]
}))
PY
}

active_director_tech_file="/tmp/president-active-tech-$$.txt"
active_director_personal_file="/tmp/president-active-personal-$$.txt"
active_chain_tech_file="/tmp/president-chain-tech-$$.txt"
active_chain_personal_file="/tmp/president-chain-personal-$$.txt"

query_agent_open "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" 2>/dev/null >"${active_director_tech_file}" &
pid_active_tech=$!
query_agent_open "${PERSONAL_DB}" NOTION_PERSONAL_API_KEY "Diretor Pessoal" 2>/dev/null >"${active_director_personal_file}" &
pid_active_personal=$!
count_chain_open_by_title_prefix "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "[Rotina Mail-Pro]" 2>/dev/null >"${active_chain_tech_file}" &
pid_chain_tech=$!
count_chain_open_by_title_prefix "${PERSONAL_DB}" NOTION_PERSONAL_API_KEY "[Rotina Mail-Person]" 2>/dev/null >"${active_chain_personal_file}" &
pid_chain_personal=$!

wait "${pid_active_tech}" "${pid_active_personal}" "${pid_chain_tech}" "${pid_chain_personal}" 2>/dev/null || true

active_director_tech="$(cat "${active_director_tech_file}" 2>/dev/null || echo 0)"
active_director_personal="$(cat "${active_director_personal_file}" 2>/dev/null || echo 0)"
[[ ! "${active_director_tech}" =~ ^[0-9]+$ ]] && active_director_tech=0
[[ ! "${active_director_personal}" =~ ^[0-9]+$ ]] && active_director_personal=0
active_chain_tech="$(cat "${active_chain_tech_file}" 2>/dev/null || echo 0)"
active_chain_personal="$(cat "${active_chain_personal_file}" 2>/dev/null || echo 0)"
[[ ! "${active_chain_tech}" =~ ^[0-9]+$ ]] && active_chain_tech=0
[[ ! "${active_chain_personal}" =~ ^[0-9]+$ ]] && active_chain_personal=0
rm -f "${active_director_tech_file}" "${active_director_personal_file}" "${active_chain_tech_file}" "${active_chain_personal_file}" 2>/dev/null || true

migration_audit="$(run_n8n_migration_audit 2>/dev/null || echo '{"ok":false,"enabled":true,"reason":"audit_failed"}')"
execution_insights="$(run_execution_insights 2>/dev/null || echo '{"ok":false,"enabled":true,"reason":"insights_failed"}')"
migration_ok="$(jq -r '.ok // false' <<<"${migration_audit}" 2>/dev/null || echo false)"
migration_enabled="$(jq -r '.enabled // false' <<<"${migration_audit}" 2>/dev/null || echo false)"
migration_missing_count="$(jq -r '.missing_count // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)"
[[ ! "${migration_missing_count}" =~ ^[0-9]+$ ]] && migration_missing_count=0
migration_missing_names="$(jq -r '.missing_names // [] | join(", ")' <<<"${migration_audit}" 2>/dev/null || true)"

existing_migration_card_id="$(find_existing_chain_card_by_prefix "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "${PRESIDENT_MIGRATION_TITLE_PREFIX}")"

if [[ "${migration_enabled}" == "true" ]] && [[ "${migration_ok}" == "true" ]]; then
  if (( migration_missing_count > 0 )); then
    if [[ -z "${existing_migration_card_id}" ]]; then
      body="/tmp/president_n8n_migration_body.txt"
      cat > "${body}" <<EOF
## Contexto
Auditoria automática do Presidente detectou lacunas na cobertura da migração OLD->NEW no n8n.

## Resultado da auditoria
- Workflows no OLD: $(jq -r '.old_count // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
- Workflows visíveis no NEW por contexto:
  - sales: $(jq -r '.new_counts.sales // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
  - product: $(jq -r '.new_counts.product // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
  - finance: $(jq -r '.new_counts.finance // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
  - sucess_client: $(jq -r '.new_counts.sucess_client // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
  - support: $(jq -r '.new_counts.support // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
  - engineering: $(jq -r '.new_counts.engineering // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
  - marketing: $(jq -r '.new_counts.marketing // 0' <<<"${migration_audit}" 2>/dev/null || echo 0)
- Faltantes detectados: ${migration_missing_count}

## Missing (amostra)
${migration_missing_names}

## Ação mandatória
1. Implementar migração dos faltantes no contexto correto.
2. Validar cobertura OLD->NEW após implementação.
3. Anexar evidência objetiva (comando + resultado) e concluir o card.
EOF
      created_json="$(NOTION_CACHE_ENABLED=true "${HELPER}" create-card "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "${PRESIDENT_MIGRATION_TITLE_PREFIX} (${migration_missing_count} faltantes)" "Aguardando" "OpenClaw" "Engenheiro de Automação" "Alta" "Presidente" "${body}" 2>/dev/null || true)"
      migration_card_id="$(jq -r '.id // ""' <<<"${created_json}" 2>/dev/null || true)"
      if [[ -n "${migration_card_id}" ]]; then
        migration_card_action="created"
      fi
    else
      migration_card_id="${existing_migration_card_id}"
      "${HELPER}" update-agent "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Engenheiro de Automação" >/dev/null || true
      "${HELPER}" update-status "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Priorizado" >/dev/null || true
      "${HELPER}" comment "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Auditoria automática do Presidente detectou ${migration_missing_count} faltante(s) na cobertura OLD->NEW. Executar implementação e anexar evidências de validação." "Presidente" >/dev/null || true
      migration_card_action="updated"
    fi
  else
    if [[ -n "${existing_migration_card_id}" ]]; then
      migration_card_id="${existing_migration_card_id}"
      "${HELPER}" comment "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Auditoria automática do Presidente confirmou cobertura OLD->NEW sem faltantes. Encerramento automático do incidente de migração." "Presidente" >/dev/null || true
      "${HELPER}" update-status "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Concluído" >/dev/null || true
      migration_card_action="closed"
    fi
  fi
elif [[ "${migration_enabled}" == "true" ]] && [[ "${migration_ok}" != "true" ]]; then
  migration_reason="$(jq -r '.reason // ""' <<<"${migration_audit}" 2>/dev/null || true)"
  if [[ "${migration_reason}" == "missing_env" ]]; then
    missing_env_list="$(jq -r '.missing_env // [] | join(", ")' <<<"${migration_audit}" 2>/dev/null || true)"
    if [[ -z "${existing_migration_card_id}" ]]; then
      body="/tmp/president_n8n_migration_env_body.txt"
      cat > "${body}" <<EOF
## Contexto
Auditoria automática da migração n8n não pôde ser executada por ausência de variáveis de ambiente.

## Variáveis ausentes
${missing_env_list}

## Ação mandatória
1. Incluir variáveis no ambiente do cron do Presidente.
2. Reexecutar auditoria automática.
3. Validar cobertura OLD->NEW.
EOF
      created_json="$(NOTION_CACHE_ENABLED=true "${HELPER}" create-card "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "${PRESIDENT_MIGRATION_TITLE_PREFIX} (env ausente)" "Aguardando" "OpenClaw" "Diretor Tech" "Alta" "Presidente" "${body}" 2>/dev/null || true)"
      migration_card_id="$(jq -r '.id // ""' <<<"${created_json}" 2>/dev/null || true)"
      [[ -n "${migration_card_id}" ]] && migration_card_action="created_env_gap"
    else
      migration_card_id="${existing_migration_card_id}"
      "${HELPER}" update-agent "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Diretor Tech" >/dev/null || true
      "${HELPER}" update-status "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Priorizado" >/dev/null || true
      "${HELPER}" comment "${migration_card_id}" NOTION_SMARTENVIOS_API_KEY "Auditoria de migração bloqueada por variáveis ausentes no ambiente do Presidente: ${missing_env_list}. Corrigir env do cron e repetir validação." "Presidente" >/dev/null || true
      migration_card_action="updated_env_gap"
    fi
  fi
fi

created_pro=0
created_personal=0
created_cards='[]'

create_card_for_domain() {
  local db_id="$1"
  local api_var="$2"
  local title="$3"
  local agent="$4"
  local priority="$5"
  local body_file="$6"

  local created_json page_id
  created_json="$(NOTION_CACHE_ENABLED=true "${HELPER}" create-card "${db_id}" "${api_var}" "${title}" "Aguardando" "OpenClaw" "${agent}" "${priority}" "Presidente" "${body_file}" 2>/dev/null || true)"
  page_id="$(jq -r '.id // empty' <<<"${created_json}" 2>/dev/null || true)"
  if [[ -n "${page_id}" ]]; then
    created_cards="$(jq -cn --argjson arr "${created_cards}" --arg id "${page_id}" '$arr + [$id]')"
    return 0
  fi
  return 1
}

should_create_pro=0
if (( unread_pro >= CREATE_THRESHOLD_PRO )) && (( active_chain_tech == 0 )); then
  if can_create_with_cooldown "pro"; then
    should_create_pro=1
  elif [[ "${CREATE_WHEN_CHAIN_EMPTY}" == "true" ]]; then
    should_create_pro=1
  fi
fi

if (( should_create_pro == 1 )); then
  body="/tmp/president_mail_pro_body.txt"
  cat > "${body}" <<EOF
## Contexto
Backlog de e-mail profissional detectado com ${unread_pro} não lidos (is:unread in:inbox).

## Objetivo
Criar demanda operacional para Diretor Tech priorizar e encaminhar para Mail-Pro.

## Escopo
- Triar 1 card por rodada até zerar backlog.
- Garantir execução real por Mail-Pro com evidências (labels/arquivamento/rascunhos quando aplicável).

## Critério de sucesso
- Card priorizado para especialista e concluído com evidência objetiva.
- Redução progressiva dos não lidos.
EOF
  if create_card_for_domain "${TECH_DB}" NOTION_SMARTENVIOS_API_KEY "[Rotina Mail-Pro] Drenagem de backlog (${unread_pro} não lidos)" "Diretor Tech" "Alta" "${body}"; then
    created_pro=1
    mark_created_now "pro"
  fi
fi

should_create_personal=0
if (( unread_personal >= CREATE_THRESHOLD_PERSONAL )) && (( active_chain_personal == 0 )); then
  if can_create_with_cooldown "personal"; then
    should_create_personal=1
  elif [[ "${CREATE_WHEN_CHAIN_EMPTY}" == "true" ]]; then
    should_create_personal=1
  fi
fi

if (( should_create_personal == 1 )); then
  body="/tmp/president_mail_person_body.txt"
  cat > "${body}" <<EOF
## Contexto
Backlog de e-mail pessoal detectado com ${unread_personal} não lidos (is:unread in:inbox).

## Objetivo
Criar demanda operacional para Diretor Pessoal priorizar e encaminhar para Mail-Person.

## Escopo
- Triar 1 card por rodada até normalizar a caixa.
- Garantir execução real por Mail-Person com evidências.

## Critério de sucesso
- Card priorizado para especialista e concluído com evidência objetiva.
- Redução progressiva dos não lidos.
EOF
  if create_card_for_domain "${PERSONAL_DB}" NOTION_PERSONAL_API_KEY "[Rotina Mail-Person] Drenagem de backlog (${unread_personal} não lidos)" "Diretor Pessoal" "Alta" "${body}"; then
    created_personal=1
    mark_created_now "personal"
  fi
fi

if [[ "${FORCE_CHAIN_ENABLED}" == "true" ]] && { (( unread_pro >= FORCE_CHAIN_THRESHOLD_PRO )) || (( unread_personal >= FORCE_CHAIN_THRESHOLD_PERSONAL )); }; then
  force_chain_triggered=1

  jq -n \
    --argjson unreadPro "${unread_pro}" \
    --argjson unreadPersonal "${unread_personal}" \
    --argjson thresholdPro "${FORCE_CHAIN_THRESHOLD_PRO}" \
    --argjson thresholdPersonal "${FORCE_CHAIN_THRESHOLD_PERSONAL}" \
    --arg reason "backlog_above_threshold" \
    --argjson createdPro "${created_pro}" \
    --argjson createdPersonal "${created_personal}" \
    --argjson at "$(date +%s)" \
    '{
      reason:$reason,
      unreadPro:$unreadPro,
      unreadPersonal:$unreadPersonal,
      thresholdPro:$thresholdPro,
      thresholdPersonal:$thresholdPersonal,
      createdPro:$createdPro,
      createdPersonal:$createdPersonal,
      requestedAt:$at
    }' > "${FORCE_FILE}.tmp" 2>/dev/null && mv "${FORCE_FILE}.tmp" "${FORCE_FILE}" 2>/dev/null || true

  if [[ "${PRESIDENT_DIRECT_WAKE_ENABLED}" == "true" ]] && can_force_wake_now; then
    # Evita sobreposição: acorda apenas a cadeia necessária por domínio.
    if (( unread_pro >= FORCE_CHAIN_THRESHOLD_PRO )) && { (( created_pro == 1 )) || (( active_chain_tech > 0 )); }; then
      force_cron_once "${DIRECTOR_TECH_CRON}" || true
      force_cron_once "${MAIL_PRO_CRON}" || true
    fi
    if (( unread_personal >= FORCE_CHAIN_THRESHOLD_PERSONAL )) && { (( created_personal == 1 )) || (( active_chain_personal > 0 )); }; then
      force_cron_once "${DIRECTOR_PERSONAL_CRON}" || true
      force_cron_once "${MAIL_PERSON_CRON}" || true
    fi
    if (( created_pro == 1 || created_personal == 1 )); then
      force_cron_once "${OPTIMIZER_CRON}" || true
    fi
    if [[ -n "${GOVERNANCE_CRON_ID}" ]]; then
      force_cron_once "${GOVERNANCE_CRON_ID}" || true
    fi
    mark_force_wake_now
  fi
fi

echo "$(jq -cn \
  --argjson unreadPro "${unread_pro}" \
  --argjson unreadPersonal "${unread_personal}" \
  --argjson thresholdPro "${CREATE_THRESHOLD_PRO}" \
  --argjson thresholdPersonal "${CREATE_THRESHOLD_PERSONAL}" \
  --argjson activeDirectorTech "${active_director_tech}" \
  --argjson activeDirectorPersonal "${active_director_personal}" \
  --argjson activeChainTech "${active_chain_tech}" \
  --argjson activeChainPersonal "${active_chain_personal}" \
  --argjson createdPro "${created_pro}" \
  --argjson createdPersonal "${created_personal}" \
  --argjson forceChainTriggered "${force_chain_triggered}" \
  --argjson forcedCrons "${forced_crons}" \
  --argjson migrationAudit "${migration_audit}" \
  --argjson executionInsights "${execution_insights}" \
  --arg migrationCardAction "${migration_card_action}" \
  --arg migrationCardId "${migration_card_id}" \
  --argjson cards "${created_cards}" \
  --arg directWake "${PRESIDENT_DIRECT_WAKE_ENABLED}" \
  '{
    ok:true,
    action:"president_mail_backlog_guard",
    unreadPro:$unreadPro,
    unreadPersonal:$unreadPersonal,
    thresholdPro:$thresholdPro,
    thresholdPersonal:$thresholdPersonal,
    activeDirectorTech:$activeDirectorTech,
    activeDirectorPersonal:$activeDirectorPersonal,
    activeChainTech:$activeChainTech,
    activeChainPersonal:$activeChainPersonal,
    createdPro:$createdPro,
    createdPersonal:$createdPersonal,
    forceChainTriggered:$forceChainTriggered,
    presidentDirectWakeEnabled:$directWake,
    forcedCrons:$forcedCrons,
    migrationAudit:$migrationAudit,
    executionInsights:$executionInsights,
    migrationCardAction:$migrationCardAction,
    migrationCardId:$migrationCardId,
    createdCards:$cards
  }')"
