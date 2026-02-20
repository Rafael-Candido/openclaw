#!/usr/bin/env bash
set -euo pipefail

# Usage:
# 0) In Google Cloud Console (OAuth client WEB), add Authorized redirect URI:
#    http://localhost:53682/oauth2callback
#    (or set GMAIL_OAUTH_REDIRECT_URI in /var/www/openclaw/.env and add that URI)
# 1) Generate auth URL:
#    ./scripts/gmail-oauth-refresh-token.sh pro url
#    ./scripts/gmail-oauth-refresh-token.sh personal url
# 2) Open URL, login/consent, copy code from redirected URL (?code=...)
# 3) Exchange AUTH_CODE for refresh token:
#    ./scripts/gmail-oauth-refresh-token.sh pro exchange "<AUTH_CODE_OR_URL_WITH_CODE>"
#    ./scripts/gmail-oauth-refresh-token.sh personal exchange "<AUTH_CODE_OR_URL_WITH_CODE>"

ENV_FILE="/var/www/openclaw/.env"
REDIRECT_URI="${GMAIL_OAUTH_REDIRECT_URI:-http://localhost:53682/oauth2callback}"
SCOPE="https://www.googleapis.com/auth/gmail.modify"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

PROFILE="${1:-}"
ACTION="${2:-url}"
CODE="${3:-}"

case "$PROFILE" in
  pro)
    CLIENT_ID="${GMAIL_PROFESSIONAL_CLIENT_ID:-}"
    CLIENT_SECRET="${GMAIL_PROFESSIONAL_CLIENT_SECRET:-}"
    ;;
  personal)
    CLIENT_ID="${GMAIL_PERSONAL_CLIENT_ID:-}"
    CLIENT_SECRET="${GMAIL_PERSONAL_CLIENT_SECRET:-}"
    ;;
  *)
    echo "Use: $0 <pro|personal> <url|exchange> [AUTH_CODE]" >&2
    exit 1
    ;;
esac

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "Missing client credentials in $ENV_FILE for profile: $PROFILE" >&2
  exit 1
fi

if [[ "$ACTION" == "url" ]]; then
  CLIENT_ID_ENV="$CLIENT_ID" REDIRECT_URI_ENV="$REDIRECT_URI" SCOPE_ENV="$SCOPE" python3 - <<'PY'
import os, urllib.parse
params = {
  "client_id": os.environ["CLIENT_ID_ENV"],
  "redirect_uri": os.environ["REDIRECT_URI_ENV"],
  "response_type": "code",
  "scope": os.environ["SCOPE_ENV"],
  "access_type": "offline",
  "prompt": "consent",
}
print("https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(params))
PY
  exit 0
fi

if [[ "$ACTION" == "exchange" ]]; then
  if [[ -z "$CODE" ]]; then
    echo "Provide AUTH_CODE for exchange." >&2
    exit 1
  fi

  # Accept either raw auth code OR full callback/URL containing ?code=...
  if [[ "$CODE" == *"code="* ]]; then
    EXTRACTED=$(python3 - "$CODE" <<'PY'
import sys, urllib.parse
raw = sys.argv[1]
# Works for full URL or query-string-like input
u = urllib.parse.urlparse(raw)
qs = urllib.parse.parse_qs(u.query if u.query else raw)
print(qs.get('code', [''])[0])
PY
)
    if [[ -n "$EXTRACTED" ]]; then
      CODE="$EXTRACTED"
    fi
  fi

  RESP=$(curl -sS -X POST https://oauth2.googleapis.com/token \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "code=$CODE" \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_secret=$CLIENT_SECRET" \
    --data-urlencode "redirect_uri=$REDIRECT_URI" \
    --data-urlencode "grant_type=authorization_code")

  if ! RESP_JSON="$RESP" python3 - <<'PY'
import json, os
raw = os.environ.get('RESP_JSON', '')
try:
  obj = json.loads(raw)
except Exception:
  print('Resposta não-JSON do Google OAuth:')
  print(raw)
  raise SystemExit(1)
if 'refresh_token' not in obj:
  print(json.dumps(obj, ensure_ascii=False, indent=2))
  raise SystemExit(1)
print(obj['refresh_token'])
PY
  then
    echo "\nDica: no passo 'exchange', cole o AUTH CODE (não a URL de autorização)." >&2
    exit 1
  fi

  exit 0
fi

echo "Unknown action: $ACTION" >&2
exit 1
