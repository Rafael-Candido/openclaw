#!/usr/bin/env bash
# Auto-unsubscribe from promotional/social emails
# Detects List-Unsubscribe headers and unsubscribe links

set -euo pipefail

PROFILE="${1:-pro}"
MSG_ID="${2:-}"
DRY_RUN="${3:-false}"

if [[ -z "$MSG_ID" ]]; then
  echo "Usage: $0 <pro|personal> <messageId> [dry-run]" >&2
  echo "  dry-run: true = only detect, false = actually unsubscribe" >&2
  exit 1
fi

GMAIL_SH="$(dirname "$0")/gmail.sh"

# Get full message
MSG=$("$GMAIL_SH" "$PROFILE" get "$MSG_ID")

# Extract headers
SUBJECT=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Subject") | .value')
FROM=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "From") | .value')
LIST_UNSUB=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "List-Unsubscribe") | .value // empty')
LABELS=$(echo "$MSG" | jq -c '.labelIds[]' | tr '\n' ',' | sed 's/,$//')

# Check if it's promotional/social (Gmail categories or sender patterns)
IS_PROMOTIONAL="false"
if echo "$LABELS" | grep -qi "CATEGORY_PROMOTIONS\|CATEGORY_SOCIAL"; then
  IS_PROMOTIONAL="true"
fi

# Check sender patterns (noreply, newsletter, marketing)
if echo "$FROM" | grep -qEi "noreply@|no-reply@|newsletter@|marketing@|promo@|offers@"; then
  IS_PROMOTIONAL="true"
fi

# Extract unsubscribe methods
UNSUB_EMAIL=""
UNSUB_URL=""

if [[ -n "$LIST_UNSUB" ]]; then
  # Parse List-Unsubscribe header (can contain email and/or URL)
  # Format: <mailto:unsub@example.com>, <https://example.com/unsub?id=123>
  
  # Extract mailto
  if echo "$LIST_UNSUB" | grep -qEi "mailto:"; then
    UNSUB_EMAIL=$(echo "$LIST_UNSUB" | grep -oE 'mailto:[^,>]+' | head -1 | sed 's/mailto://')
  fi
  
  # Extract https URL
  if echo "$LIST_UNSUB" | grep -qEi "https?://"; then
    UNSUB_URL=$(echo "$LIST_UNSUB" | grep -oE 'https?://[^,> ]+' | head -1)
  fi
fi

# Determine action
CAN_UNSUB="false"
UNSUB_METHOD="none"

if [[ -n "$UNSUB_URL" ]]; then
  CAN_UNSUB="true"
  UNSUB_METHOD="url"
elif [[ -n "$UNSUB_EMAIL" ]]; then
  CAN_UNSUB="true"
  UNSUB_METHOD="email"
fi

# Build result
RESULT=$(jq -n \
  --arg id "$MSG_ID" \
  --arg subject "$SUBJECT" \
  --arg from "$FROM" \
  --arg promo "$IS_PROMOTIONAL" \
  --arg canUnsub "$CAN_UNSUB" \
  --arg method "$UNSUB_METHOD" \
  --arg email "$UNSUB_EMAIL" \
  --arg url "$UNSUB_URL" \
  '{
    messageId: $id,
    subject: $subject,
    from: $from,
    isPromotional: $promo,
    canUnsubscribe: $canUnsub,
    unsubscribeMethod: $method,
    unsubscribeEmail: $email,
    unsubscribeUrl: $url
  }')

# Execute unsubscribe if not dry-run
if [[ "$DRY_RUN" == "false" && "$CAN_UNSUB" == "true" && "$IS_PROMOTIONAL" == "true" ]]; then
  if [[ "$UNSUB_METHOD" == "url" ]]; then
    # Visit unsubscribe URL (HEAD request to trigger)
    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" -X GET "$UNSUB_URL" -L --max-time 10 || echo "000")
    RESULT=$(echo "$RESULT" | jq --arg code "$HTTP_CODE" '. + {unsubscribeStatus: $code}')
    
    if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
      RESULT=$(echo "$RESULT" | jq '. + {unsubscribeExecuted: true}')
    else
      RESULT=$(echo "$RESULT" | jq '. + {unsubscribeExecuted: false, unsubscribeError: "HTTP '"$HTTP_CODE"'"}')
    fi
  elif [[ "$UNSUB_METHOD" == "email" ]]; then
    # Send unsubscribe email (via Gmail draft, requires manual send)
    RESULT=$(echo "$RESULT" | jq '. + {unsubscribeExecuted: false, unsubscribeNote: "Email unsubscribe requires manual draft review"}')
  fi
else
  RESULT=$(echo "$RESULT" | jq '. + {unsubscribeExecuted: false, dryRun: true}')
fi

echo "$RESULT" | jq .
