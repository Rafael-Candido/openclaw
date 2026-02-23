#!/usr/bin/env bash
# Gmail triage workflow for Mail-Pro and Mail-Person
# Usage: ./triage.sh <profile> [limit]
# Returns JSON with unread messages + metadata for agent decision

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-100}"
UNREAD_QUERY="${MAIL_UNREAD_QUERY:-is:unread in:inbox}"

GMAIL_SH="$(dirname "$0")/gmail.sh"

if [[ ! -x "$GMAIL_SH" ]]; then
  echo "Error: gmail.sh not found or not executable" >&2
  exit 1
fi

# Get unread messages from inbox (maxResults = LIMIT para suportar 200+ quando necessário)
LIST_JSON="$("$GMAIL_SH" "$PROFILE" list "$UNREAD_QUERY" "$LIMIT" 2>/dev/null || echo '{}')"
TOTAL_ESTIMATE="$(echo "$LIST_JSON" | jq -r '.resultSizeEstimate // 0' 2>/dev/null || echo 0)"
UNREAD="$(echo "$LIST_JSON" | jq -r ".messages[0:$LIMIT] // [] | .[]?.id" 2>/dev/null || echo "")"

if [[ -z "$UNREAD" ]]; then
  echo '{"unread": 0, "messages": []}'
  exit 0
fi

# Fetch full message data for each
MESSAGES="[]"
COUNT=0

while IFS= read -r MSG_ID; do
  [[ -z "$MSG_ID" ]] && continue
  
  MSG_DATA=$("$GMAIL_SH" "$PROFILE" get "$MSG_ID")
  
  # Extract key fields (incl. To/Cc e headers para análise sem chamada extra)
  SUBJECT=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "Subject") | .value')
  FROM=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "From") | .value')
  TO=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "To") | .value // ""')
  CC=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "Cc") | .value // ""')
  DATE=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "Date") | .value')
  SNIPPET=$(echo "$MSG_DATA" | jq -r '.snippet')
  THREAD_ID=$(echo "$MSG_DATA" | jq -r '.threadId')
  LABELS=$(echo "$MSG_DATA" | jq -c '.labelIds')
  AUTO_SUBMITTED=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "Auto-Submitted") | .value // ""')
  PRECEDENCE=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "Precedence") | .value // ""')
  X_AUTOREPLY=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "X-Autoreply" or .name == "X-Auto-Response-Suppress") | .value // ""')
  
  # Build message object (workflow usa isso sem chamar analyze.sh = 1 list + N get em vez de 1 list + 2N get + N thread)
  MSG_OBJ=$(jq -n \
    --arg id "$MSG_ID" \
    --arg thread "$THREAD_ID" \
    --arg subject "$SUBJECT" \
    --arg from "$FROM" \
    --arg to "$TO" \
    --arg cc "$CC" \
    --arg date "$DATE" \
    --arg snippet "$SNIPPET" \
    --arg auto "$AUTO_SUBMITTED" \
    --arg prec "$PRECEDENCE" \
    --arg xauto "$X_AUTOREPLY" \
    --argjson labels "$LABELS" \
    '{id: $id, threadId: $thread, subject: $subject, from: $from, to: $to, cc: $cc, date: $date, snippet: $snippet, autoSubmitted: $auto, precedence: $prec, xAutorreply: $xauto, labels: $labels}')
  
  MESSAGES=$(echo "$MESSAGES" | jq --argjson msg "$MSG_OBJ" '. + [$msg]')
  
  COUNT=$((COUNT + 1))
  echo "Fetched $COUNT/$LIMIT..." >&2
  
done <<< "$UNREAD"

# Return JSON report
jq -n \
  --argjson count "$TOTAL_ESTIMATE" \
  --argjson selected "$COUNT" \
  --argjson messages "$MESSAGES" \
  --arg profile "$PROFILE" \
  '{profile: $profile, unread: $count, selected: $selected, messages: $messages}'
