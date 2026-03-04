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

OLD_URL="${OLD_N8N_URL:-}"
OLD_KEY="${OLD_N8N_API_KEY:-}"
NEW_BASE="${N8N_API_BASE_URL:-https://n8n.smartenvios.tec.br/api/v1}"
SALES_KEY="${N8N_SALES_API_KEY:-}"
PRODUCT_KEY="${N8N_PRODUCT_API_KEY:-}"
FINANCE_KEY="${N8N_FINANCE_API_KEY:-}"
SUCESS_CLIENT_KEY="${N8N_SUCESS_CLIENT_API_KEY:-}"
SUPPORT_KEY="${N8N_SUPPORT_API_KEY:-}"
ENGINEERING_KEY="${N8N_ENGINEERING_API_KEY:-}"
MARKETING_KEY="${N8N_MARKETING_API_KEY:-}"

LIMIT="${LIMIT:-250}"
DRY_RUN="${DRY_RUN:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    --apply) DRY_RUN="false"; shift ;;
    --limit) LIMIT="${2:-250}"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "${OLD_URL}" ]] || { echo "OLD_N8N_URL missing"; exit 1; }
[[ -n "${OLD_KEY}" ]] || { echo "OLD_N8N_API_KEY missing"; exit 1; }
[[ -n "${SALES_KEY}" ]] || { echo "N8N_SALES_API_KEY missing"; exit 1; }
[[ -n "${PRODUCT_KEY}" ]] || { echo "N8N_PRODUCT_API_KEY missing"; exit 1; }
[[ -n "${FINANCE_KEY}" ]] || { echo "N8N_FINANCE_API_KEY missing"; exit 1; }
[[ -n "${SUCESS_CLIENT_KEY}" ]] || { echo "N8N_SUCESS_CLIENT_API_KEY missing"; exit 1; }
[[ -n "${SUPPORT_KEY}" ]] || { echo "N8N_SUPPORT_API_KEY missing"; exit 1; }
[[ -n "${ENGINEERING_KEY}" ]] || { echo "N8N_ENGINEERING_API_KEY missing"; exit 1; }
[[ -n "${MARKETING_KEY}" ]] || { echo "N8N_MARKETING_API_KEY missing"; exit 1; }

OLD_BASE="${OLD_URL%/}/api/v1"

ctx_key() {
  case "$1" in
    sales) printf '%s' "${SALES_KEY}" ;;
    product) printf '%s' "${PRODUCT_KEY}" ;;
    finance) printf '%s' "${FINANCE_KEY}" ;;
    success-client|sucess-client) printf '%s' "${SUCESS_CLIENT_KEY}" ;;
    support) printf '%s' "${SUPPORT_KEY}" ;;
    engineering) printf '%s' "${ENGINEERING_KEY}" ;;
    marketing) printf '%s' "${MARKETING_KEY}" ;;
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

# index target names to avoid duplicates
mkdir -p /tmp/n8n-migrate
for ctx in sales product finance success-client support engineering marketing; do
  key="$(ctx_key "$ctx")"
  curl -sS -H "X-N8N-API-KEY: ${key}" "${NEW_BASE}/workflows?limit=500" > "/tmp/n8n-migrate/${ctx}.json"
done

curl -sS -H "X-N8N-API-KEY: ${OLD_KEY}" "${OLD_BASE}/workflows?limit=${LIMIT}" > /tmp/n8n-migrate/old.json

python3 - <<'PY' > /tmp/n8n-migrate/list.tsv
import json
old=json.load(open('/tmp/n8n-migrate/old.json'))
for w in old.get('data',[]):
    tags=','.join([(t.get('name') or '') for t in (w.get('tags') or [])])
    print(f"{w.get('id','')}\t{(w.get('name') or '').replace(chr(9),' ')}\t{tags}")
PY

ok=0; skip=0; fail=0
while IFS=$'\t' read -r wid wname wtags; do
  [[ -z "${wid}" ]] && continue
  ctx="$(classify "${wname}" "${wtags}")"
  key="$(ctx_key "${ctx}")"

  exists="$(python3 - "$ctx" "$wname" <<'PY'
import json,sys
ctx=sys.argv[1]; name=sys.argv[2]
data=json.load(open(f'/tmp/n8n-migrate/{ctx}.json'))
for w in data.get('data',[]):
    if (w.get('name') or '') == name:
        print(w.get('id') or '')
        raise SystemExit
print('')
PY
)"

  if [[ -n "${exists}" ]]; then
    echo "SKIP\t${ctx}\t${wid}\t${wname}\talready_exists:${exists}"
    skip=$((skip+1))
    continue
  fi

  curl -sS -H "X-N8N-API-KEY: ${OLD_KEY}" "${OLD_BASE}/workflows/${wid}" > /tmp/n8n-migrate/wf-${wid}.json
  jq '{name, nodes, connections, settings:{executionOrder:(.settings.executionOrder // "v1")}}' "/tmp/n8n-migrate/wf-${wid}.json" > "/tmp/n8n-migrate/payload-${wid}.json"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY\t${ctx}\t${wid}\t${wname}\tready"
    ok=$((ok+1))
    continue
  fi

  code="$(curl -sS -o "/tmp/n8n-migrate/resp-${wid}.json" -w "%{http_code}" -X POST "${NEW_BASE}/workflows" -H "Content-Type: application/json" -H "X-N8N-API-KEY: ${key}" --data-binary @"/tmp/n8n-migrate/payload-${wid}.json")"
  if [[ "${code}" == "200" || "${code}" == "201" ]]; then
    nid="$(jq -r '.id // ""' "/tmp/n8n-migrate/resp-${wid}.json")"
    echo "OK\t${ctx}\t${wid}\t${wname}\tnew:${nid}"
    ok=$((ok+1))
  else
    echo "FAIL\t${ctx}\t${wid}\t${wname}\thttp:${code}"
    fail=$((fail+1))
  fi
done < /tmp/n8n-migrate/list.tsv

echo "SUMMARY ok=${ok} skip=${skip} fail=${fail} dry_run=${DRY_RUN}"
