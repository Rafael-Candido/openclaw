#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set +e
  set +u
  # shellcheck disable=SC1090
  source "${ENV_FILE}" >/dev/null 2>&1
  set -u
  set -e
fi

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

BASE_URL="${N8N_API_BASE_URL:-https://n8n.smartenvios.tec.br/api/v1}"
PRODUCT_KEY="${N8N_PRODUCT_API_KEY:-$(read_env_var N8N_PRODUCT_API_KEY "${ENV_FILE}")}"
SALES_KEY="${N8N_SALES_API_KEY:-$(read_env_var N8N_SALES_API_KEY "${ENV_FILE}")}"
FINANCE_KEY="${N8N_FINANCE_API_KEY:-$(read_env_var N8N_FINANCE_API_KEY "${ENV_FILE}")}"
SUCESS_CLIENT_KEY="${N8N_SUCESS_CLIENT_API_KEY:-$(read_env_var N8N_SUCESS_CLIENT_API_KEY "${ENV_FILE}")}"
SUPPORT_KEY="${N8N_SUPPORT_API_KEY:-$(read_env_var N8N_SUPPORT_API_KEY "${ENV_FILE}")}"
ENGINEERING_KEY="${N8N_ENGINEERING_API_KEY:-$(read_env_var N8N_ENGINEERING_API_KEY "${ENV_FILE}")}"
MARKETING_KEY="${N8N_MARKETING_API_KEY:-$(read_env_var N8N_MARKETING_API_KEY "${ENV_FILE}")}"

DRY_RUN=true
DELETE_SOURCE=true
LIMIT="${LIMIT:-250}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --apply) DRY_RUN=false; shift ;;
    --no-delete-source) DELETE_SOURCE=false; shift ;;
    --delete-source) DELETE_SOURCE=true; shift ;;
    --limit) LIMIT="${2:-500}"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

if [[ ! "${LIMIT}" =~ ^[0-9]+$ ]]; then
  LIMIT=250
fi
if (( LIMIT > 250 )); then
  LIMIT=250
fi

[[ -n "${PRODUCT_KEY}" ]] || { echo "N8N_PRODUCT_API_KEY missing"; exit 1; }
[[ -n "${SALES_KEY}" ]] || { echo "N8N_SALES_API_KEY missing"; exit 1; }
[[ -n "${FINANCE_KEY}" ]] || { echo "N8N_FINANCE_API_KEY missing"; exit 1; }
[[ -n "${SUCESS_CLIENT_KEY}" ]] || { echo "N8N_SUCESS_CLIENT_API_KEY missing"; exit 1; }
[[ -n "${SUPPORT_KEY}" ]] || { echo "N8N_SUPPORT_API_KEY missing"; exit 1; }
[[ -n "${ENGINEERING_KEY}" ]] || { echo "N8N_ENGINEERING_API_KEY missing"; exit 1; }
[[ -n "${MARKETING_KEY}" ]] || { echo "N8N_MARKETING_API_KEY missing"; exit 1; }

ctx_key() {
  case "$1" in
    sales) printf '%s' "${SALES_KEY}" ;;
    finance) printf '%s' "${FINANCE_KEY}" ;;
    success-client|sucess-client) printf '%s' "${SUCESS_CLIENT_KEY}" ;;
    support) printf '%s' "${SUPPORT_KEY}" ;;
    engineering) printf '%s' "${ENGINEERING_KEY}" ;;
    marketing) printf '%s' "${MARKETING_KEY}" ;;
    product) printf '%s' "${PRODUCT_KEY}" ;;
    *) return 1 ;;
  esac
}

classify() {
  local name="$1"
  local tags_csv="$2"
  python3 - "$name" "$tags_csv" <<'PY'
import re,sys
name=(sys.argv[1] or '').lower()
tags=(sys.argv[2] or '').lower()
text=f"{name} {tags}"
if re.search(r'finan|fatur|boleto|conta|pagament|receb|tesour|fiscal', text):
    print('finance')
elif re.search(r'sucess|success|cliente|customer success|csat|nps|onboard|onboarding|reten', text):
    print('success-client')
elif re.search(r'support|suporte|ticket|atendimento|zendesk|helpdesk|pendenc|pendency|delayed|sla', text):
    print('support')
elif re.search(r'engineer|engineering|devops|deploy|ci|cd|infra|sre|k8s|kubernetes|argocd|terraform', text):
    print('engineering')
elif re.search(r'marketing|campanha|campaign|mkt|utm|meta ads|google ads|growth|rd station', text):
    print('marketing')
elif re.search(r'sales|venda|comercial|lead|crm|pipedrive|pre-venda|pré-venda', text):
    print('sales')
else:
    print('product')
PY
}

mkdir -p /tmp/n8n-redist
contexts=(sales finance success-client support engineering marketing)
for ctx in "${contexts[@]}"; do
  key="$(ctx_key "$ctx")"
  curl -sS -H "X-N8N-API-KEY: ${key}" "${BASE_URL}/workflows?limit=500" > "/tmp/n8n-redist/${ctx}.json"
done
curl -sS -H "X-N8N-API-KEY: ${PRODUCT_KEY}" "${BASE_URL}/workflows?limit=${LIMIT}" > "/tmp/n8n-redist/product.json"

python3 - <<'PY' > /tmp/n8n-redist/list.tsv
import json
data=json.load(open('/tmp/n8n-redist/product.json'))
for w in data.get('data',[]):
    tags=','.join([(t.get('name') or '') for t in (w.get('tags') or [])])
    print(f"{w.get('id','')}\t{(w.get('name') or '').replace(chr(9),' ')}\t{tags}")
PY

ok=0; skip=0; fail=0; deleted=0
while IFS=$'\t' read -r wid wname wtags; do
  [[ -z "${wid}" ]] && continue
  target_ctx="$(classify "${wname}" "${wtags}")"
  if [[ "${target_ctx}" == "product" ]]; then
    echo "KEEP\tproduct\t${wid}\t${wname}\tclassified=product"
    skip=$((skip+1))
    continue
  fi

  exists="$(python3 - "$target_ctx" "$wname" <<'PY'
import json,sys
ctx=sys.argv[1]; name=sys.argv[2]
data=json.load(open(f'/tmp/n8n-redist/{ctx}.json'))
for w in data.get('data',[]):
    if (w.get('name') or '') == name:
        print(w.get('id') or '')
        raise SystemExit
print('')
PY
)"

  if [[ -n "${exists}" ]]; then
    if [[ "${DRY_RUN}" == "false" && "${DELETE_SOURCE}" == "true" ]]; then
      code_del="$(curl -sS -o /tmp/n8n-redist/del-${wid}.json -w "%{http_code}" -X DELETE "${BASE_URL}/workflows/${wid}" -H "X-N8N-API-KEY: ${PRODUCT_KEY}")"
      if [[ "${code_del}" == "200" || "${code_del}" == "204" ]]; then
        echo "OK\t${target_ctx}\t${wid}\t${wname}\texists:${exists};deleted_source"
        deleted=$((deleted+1))
        ok=$((ok+1))
      else
        echo "FAIL\t${target_ctx}\t${wid}\t${wname}\texists:${exists};delete_http:${code_del}"
        fail=$((fail+1))
      fi
    else
      echo "SKIP\t${target_ctx}\t${wid}\t${wname}\talready_exists:${exists}"
      skip=$((skip+1))
    fi
    continue
  fi

  curl -sS -H "X-N8N-API-KEY: ${PRODUCT_KEY}" "${BASE_URL}/workflows/${wid}" > "/tmp/n8n-redist/wf-${wid}.json"
  jq '{name, nodes, connections, settings:{executionOrder:(.settings.executionOrder // "v1")}}' "/tmp/n8n-redist/wf-${wid}.json" > "/tmp/n8n-redist/payload-${wid}.json"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY\t${target_ctx}\t${wid}\t${wname}\tready"
    ok=$((ok+1))
    continue
  fi

  target_key="$(ctx_key "${target_ctx}")"
  code_post="$(curl -sS -o "/tmp/n8n-redist/post-${wid}.json" -w "%{http_code}" -X POST "${BASE_URL}/workflows" -H "Content-Type: application/json" -H "X-N8N-API-KEY: ${target_key}" --data-binary @"/tmp/n8n-redist/payload-${wid}.json")"
  if [[ "${code_post}" != "200" && "${code_post}" != "201" ]]; then
    echo "FAIL\t${target_ctx}\t${wid}\t${wname}\tpost_http:${code_post}"
    fail=$((fail+1))
    continue
  fi

  new_id="$(jq -r '.id // ""' "/tmp/n8n-redist/post-${wid}.json")"
  if [[ "${DELETE_SOURCE}" == "true" ]]; then
    code_del="$(curl -sS -o /tmp/n8n-redist/del-${wid}.json -w "%{http_code}" -X DELETE "${BASE_URL}/workflows/${wid}" -H "X-N8N-API-KEY: ${PRODUCT_KEY}")"
    if [[ "${code_del}" == "200" || "${code_del}" == "204" ]]; then
      deleted=$((deleted+1))
      echo "OK\t${target_ctx}\t${wid}\t${wname}\tnew:${new_id};deleted_source"
      ok=$((ok+1))
    else
      echo "FAIL\t${target_ctx}\t${wid}\t${wname}\tnew:${new_id};delete_http:${code_del}"
      fail=$((fail+1))
    fi
  else
    echo "OK\t${target_ctx}\t${wid}\t${wname}\tnew:${new_id}"
    ok=$((ok+1))
  fi
done < /tmp/n8n-redist/list.tsv

echo "SUMMARY ok=${ok} skip=${skip} fail=${fail} deleted=${deleted} dry_run=${DRY_RUN} delete_source=${DELETE_SOURCE}"
