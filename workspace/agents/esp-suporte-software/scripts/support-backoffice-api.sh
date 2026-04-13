#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Uso:
  support-backoffice-api.sh <service> <METHOD> <path> [json_body]

service: plataform | central | crm
METHOD : GET | POST | PUT | PATCH | DELETE
path   : caminho relativo (/health) ou URL absoluta
USAGE
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

SERVICE="$1"
METHOD="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
TARGET_PATH="$3"
BODY="${4:-}"

ROOT_ENV="/var/www/openclaw/.env"
if [[ -f "$ROOT_ENV" ]]; then
  set +e +u
  # shellcheck disable=SC1090
  source "$ROOT_ENV" >/dev/null 2>&1
  set -euo pipefail
fi

# Compatibilidade com nomes alternativos (lower/upper/sinônimos comuns).
PLATAFORM_URL="${plataform_production_url:-${platform_production_url:-${PLATFORM_PRODUCTION_URL:-${PLATAFORM_PRODUCTION_URL:-}}}}"
CENTRAL_URL_RAW="${central_production_url:-${CENTRAL_PRODUCTION_URL:-${central_url:-${CENTRAL_URL:-}}}}"
CRM_URL_RAW="${crm_production_url:-${CRM_PRODUCTION_URL:-${crm_url:-${CRM_URL:-}}}}"
BASIC_USER="${plataform_production_username:-${platform_production_username:-${PLATFORM_PRODUCTION_USERNAME:-${PLATAFORM_PRODUCTION_USERNAME:-}}}}"
BASIC_PASS="${plataform_production_password:-${platform_production_password:-${PLATFORM_PRODUCTION_PASSWORD:-${PLATAFORM_PRODUCTION_PASSWORD:-}}}}"

# Por padrão, central/crm podem reaproveitar base da plataforma quando não configuradas.
ALLOW_FALLBACK="${SUPPORT_BACKOFFICE_ALLOW_FALLBACK:-true}"
CENTRAL_FALLBACK_USED=false
CRM_FALLBACK_USED=false
CENTRAL_URL="$CENTRAL_URL_RAW"
CRM_URL="$CRM_URL_RAW"
if [[ -z "$CENTRAL_URL" && "$ALLOW_FALLBACK" == "true" ]]; then
  CENTRAL_URL="$PLATAFORM_URL"
  CENTRAL_FALLBACK_USED=true
fi
if [[ -z "$CRM_URL" && "$ALLOW_FALLBACK" == "true" ]]; then
  CRM_URL="$PLATAFORM_URL"
  CRM_FALLBACK_USED=true
fi

case "$SERVICE" in
  plataform) BASE_URL="$PLATAFORM_URL" ;;
  central) BASE_URL="$CENTRAL_URL" ;;
  crm) BASE_URL="$CRM_URL" ;;
  *) echo '{"ok":false,"error":"invalid_service"}'; exit 2 ;;
esac

if [[ -z "$BASE_URL" ]]; then
  echo "{\"ok\":false,\"error\":\"missing_base_url\",\"service\":\"$SERVICE\"}"
  exit 3
fi
if [[ -z "$BASIC_USER" || -z "$BASIC_PASS" ]]; then
  echo "{\"ok\":false,\"error\":\"missing_basic_auth\"}"
  exit 4
fi

if [[ "$TARGET_PATH" =~ ^https?:// ]]; then
  URL="$TARGET_PATH"
else
  URL="${BASE_URL%/}/${TARGET_PATH#/}"
fi

TMP_BODY="$(mktemp)"
trap 'rm -f "$TMP_BODY"' EXIT

CURL_ARGS=(
  -sS
  -u "$BASIC_USER:$BASIC_PASS"
  -X "$METHOD"
  -H "Accept: application/json"
  "$URL"
  -o "$TMP_BODY"
  -w "%{http_code}"
)

if [[ -n "$BODY" ]]; then
  CURL_ARGS=(
    -sS
    -u "$BASIC_USER:$BASIC_PASS"
    -X "$METHOD"
    -H "Accept: application/json"
    -H "Content-Type: application/json"
    --data "$BODY"
    "$URL"
    -o "$TMP_BODY"
    -w "%{http_code}"
  )
fi

HTTP_CODE="$(curl "${CURL_ARGS[@]}" || true)"
[[ -z "$HTTP_CODE" ]] && HTTP_CODE="000"

python3 - "$HTTP_CODE" "$SERVICE" "$URL" "$TMP_BODY" "$CENTRAL_FALLBACK_USED" "$CRM_FALLBACK_USED" "$ALLOW_FALLBACK" <<'PY'
import json
import pathlib
import sys

code = sys.argv[1]
service = sys.argv[2]
url = sys.argv[3]
body_path = pathlib.Path(sys.argv[4])
central_fallback_used = (sys.argv[5] or "").strip().lower() == "true"
crm_fallback_used = (sys.argv[6] or "").strip().lower() == "true"
allow_fallback = (sys.argv[7] or "").strip().lower() == "true"

try:
    status = int(code)
except Exception:
    status = 0

raw = body_path.read_text(encoding="utf-8", errors="replace") if body_path.exists() else ""
parsed = None
if raw.strip():
    try:
        parsed = json.loads(raw)
    except Exception:
        parsed = None

payload = {
    "ok": 200 <= status < 400,
    "service": service,
    "url": url,
    "http_status": status,
    "config": {
        "allow_fallback": allow_fallback,
        "central_fallback_used": central_fallback_used,
        "crm_fallback_used": crm_fallback_used,
        "service_fallback_used": (
            central_fallback_used if service == "central"
            else crm_fallback_used if service == "crm"
            else False
        ),
    },
}
if parsed is not None:
    payload["body"] = parsed
else:
    payload["body_raw"] = raw[:4000]

print(json.dumps(payload, ensure_ascii=False))
PY
