#!/usr/bin/env bash
# Gmail API wrapper for Mail-Pro and Mail-Person specialists
# Usage: ./gmail.sh <profile> <action> [args...]
# Profiles: pro | personal
# Actions: auth, list, get, thread, labels, label-create, label-apply, mark-read, draft-create, archive

set -euo pipefail

PROFILE="${1:-}"
ACTION="${2:-}"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}"

if [[ -z "$PROFILE" || -z "$ACTION" ]]; then
  echo "Usage: $0 <pro|personal> <action> [args...]" >&2
  echo "" >&2
  echo "Actions:" >&2
  echo "  auth                           - Get access token (cached 50min)" >&2
  echo "  list [query]                   - List messages (default: is:unread)" >&2
  echo "  get <msgId>                    - Get single message" >&2
  echo "  thread <threadId>              - Get full thread with history" >&2
  echo "  labels                         - List all labels" >&2
  echo "  label-create <name>            - Create label (or get existing)" >&2
  echo "  label-apply <msgId> <labelId>  - Apply label to message" >&2
  echo "  mark-read <msgId>              - Mark message as read (remove UNREAD)" >&2
  echo "  draft-create <to> <subject> <body> [threadId] - Create draft" >&2
  echo "  archive <msgId>                - Archive message (remove INBOX)" >&2
  exit 1
fi

# Load environment
if [[ -f "${OPENCLAW_CONFIG_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  source "${OPENCLAW_CONFIG_DIR}/.env"
  set +a
fi

# Select credentials by profile
case "$PROFILE" in
  pro)
    CLIENT_ID="${GMAIL_PROFESSIONAL_CLIENT_ID:-}"
    CLIENT_SECRET="${GMAIL_PROFESSIONAL_CLIENT_SECRET:-}"
    REFRESH_TOKEN="${GMAIL_PROFESSIONAL_REFRESH_TOKEN:-}"
    EMAIL="rafael.pereira@smartenvios.com"
    ;;
  personal)
    CLIENT_ID="${GMAIL_PERSONAL_CLIENT_ID:-}"
    CLIENT_SECRET="${GMAIL_PERSONAL_CLIENT_SECRET:-}"
    REFRESH_TOKEN="${GMAIL_PERSONAL_REFRESH_TOKEN:-}"
    EMAIL="rafael.silva.pereira10@gmail.com"
    ;;
  *)
    echo "Invalid profile: $PROFILE (use 'pro' or 'personal')" >&2
    exit 1
    ;;
esac

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$REFRESH_TOKEN" ]]; then
  echo "Missing credentials for profile: $PROFILE" >&2
  echo "Required env vars: GMAIL_${PROFILE^^}_CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN" >&2
  exit 1
fi

# Token cache
TOKEN_CACHE="/tmp/gmail-token-${PROFILE}.cache"
TOKEN_CACHE_TTL=3000  # 50 minutes (tokens last 1h, refresh before expiry)

# Get access token (cached)
get_access_token() {
  if [[ -f "$TOKEN_CACHE" ]]; then
    CACHE_AGE=$(($(date +%s) - $(stat -f%m "$TOKEN_CACHE" 2>/dev/null || stat -c%Y "$TOKEN_CACHE" 2>/dev/null || echo 0)))
    if [[ $CACHE_AGE -lt $TOKEN_CACHE_TTL ]]; then
      cat "$TOKEN_CACHE"
      return 0
    fi
  fi

  # Refresh token
  RESP=$(curl -sS -X POST https://oauth2.googleapis.com/token \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_secret=$CLIENT_SECRET" \
    --data-urlencode "refresh_token=$REFRESH_TOKEN" \
    --data-urlencode "grant_type=refresh_token")

  ACCESS_TOKEN=$(echo "$RESP" | jq -r '.access_token // empty')
  
  if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Failed to refresh access token for profile: $PROFILE" >&2
    echo "$RESP" | jq . >&2
    exit 1
  fi

  echo "$ACCESS_TOKEN" > "$TOKEN_CACHE"
  echo "$ACCESS_TOKEN"
}

# Gmail API call
gmail_api() {
  local METHOD="$1"
  local ENDPOINT="$2"
  shift 2
  
  ACCESS_TOKEN=$(get_access_token)
  
  curl -sS -X "$METHOD" \
    "https://gmail.googleapis.com/gmail/v1/users/me/${ENDPOINT}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

# Actions
case "$ACTION" in
  auth)
    get_access_token
    echo " (cached at $TOKEN_CACHE)" >&2
    ;;

  list)
    QUERY="${3:-is:unread}"
    gmail_api GET "messages?q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$QUERY'''))")"
    ;;

  get)
    MSG_ID="${3:-}"
    if [[ -z "$MSG_ID" ]]; then
      echo "Usage: $0 $PROFILE get <messageId>" >&2
      exit 1
    fi
    gmail_api GET "messages/$MSG_ID?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date"
    ;;

  thread)
    THREAD_ID="${3:-}"
    if [[ -z "$THREAD_ID" ]]; then
      echo "Usage: $0 $PROFILE thread <threadId>" >&2
      exit 1
    fi
    gmail_api GET "threads/$THREAD_ID?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date"
    ;;

  labels)
    gmail_api GET "labels"
    ;;

  label-create)
    LABEL_NAME="${3:-}"
    if [[ -z "$LABEL_NAME" ]]; then
      echo "Usage: $0 $PROFILE label-create <labelName>" >&2
      exit 1
    fi
    
    # Check if label exists first
    EXISTING=$(gmail_api GET "labels" | jq -r ".labels[] | select(.name == \"$LABEL_NAME\") | .id")
    if [[ -n "$EXISTING" ]]; then
      echo "{\"id\": \"$EXISTING\", \"name\": \"$LABEL_NAME\", \"existed\": true}" | jq .
      exit 0
    fi
    
    # Create new label
    gmail_api POST "labels" -d "{\"name\": \"$LABEL_NAME\", \"labelListVisibility\": \"labelShow\", \"messageListVisibility\": \"show\"}"
    ;;

  label-apply)
    MSG_ID="${3:-}"
    LABEL_ID="${4:-}"
    if [[ -z "$MSG_ID" || -z "$LABEL_ID" ]]; then
      echo "Usage: $0 $PROFILE label-apply <messageId> <labelId>" >&2
      exit 1
    fi
    gmail_api POST "messages/$MSG_ID/modify" -d "{\"addLabelIds\": [\"$LABEL_ID\"]}"
    ;;

  mark-read)
    MSG_ID="${3:-}"
    if [[ -z "$MSG_ID" ]]; then
      echo "Usage: $0 $PROFILE mark-read <messageId>" >&2
      exit 1
    fi
    gmail_api POST "messages/$MSG_ID/modify" -d '{"removeLabelIds": ["UNREAD"]}'
    ;;

  draft-create)
    TO="${3:-}"
    SUBJECT="${4:-}"
    BODY="${5:-}"
    THREAD_ID="${6:-}"
    
    if [[ -z "$TO" || -z "$SUBJECT" || -z "$BODY" ]]; then
      echo "Usage: $0 $PROFILE draft-create <to> <subject> <body> [threadId]" >&2
      exit 1
    fi
    
    # Build email in RFC 2822 format
    EMAIL_RAW="From: $EMAIL
To: $TO
Subject: $SUBJECT

$BODY"

    # Base64 encode (URL-safe)
    EMAIL_B64=$(echo -n "$EMAIL_RAW" | base64 | tr '+/' '-_' | tr -d '=\n')
    
    # Build request
    if [[ -n "$THREAD_ID" ]]; then
      REQUEST="{\"message\": {\"raw\": \"$EMAIL_B64\", \"threadId\": \"$THREAD_ID\"}}"
    else
      REQUEST="{\"message\": {\"raw\": \"$EMAIL_B64\"}}"
    fi
    
    gmail_api POST "drafts" -d "$REQUEST"
    ;;

  archive)
    MSG_ID="${3:-}"
    if [[ -z "$MSG_ID" ]]; then
      echo "Usage: $0 $PROFILE archive <messageId>" >&2
      exit 1
    fi
    gmail_api POST "messages/$MSG_ID/modify" -d '{"removeLabelIds": ["INBOX"]}'
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    exit 1
    ;;
esac
