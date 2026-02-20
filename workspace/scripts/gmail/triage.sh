#!/usr/bin/env bash
# Gmail triage workflow for Mail-Pro and Mail-Person
# Usage: ./triage.sh <profile> [limit]
# Returns JSON with unread messages + metadata for agent decision

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-100}"

GMAIL_SH="$(dirname "$0")/gmail.sh"

if [[ ! -x "$GMAIL_SH" ]]; then
  echo "Error: gmail.sh not found or not executable" >&2
  exit 1
fi

# Get unread messages
UNREAD=$("$GMAIL_SH" "$PROFILE" list "is:unread" | jq -r ".messages[0:$LIMIT] | .[] | .id" 2>/dev/null || echo "")

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
  
  # Extract key fields
  SUBJECT=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "Subject") | .value')
  FROM=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "From") | .value')
  DATE=$(echo "$MSG_DATA" | jq -r '.payload.headers[] | select(.name == "Date") | .value')
  SNIPPET=$(echo "$MSG_DATA" | jq -r '.snippet')
  THREAD_ID=$(echo "$MSG_DATA" | jq -r '.threadId')
  LABELS=$(echo "$MSG_DATA" | jq -c '.labelIds')
  
  # Build message object
  MSG_OBJ=$(jq -n \
    --arg id "$MSG_ID" \
    --arg thread "$THREAD_ID" \
    --arg subject "$SUBJECT" \
    --arg from "$FROM" \
    --arg date "$DATE" \
    --arg snippet "$SNIPPET" \
    --argjson labels "$LABELS" \
    '{id: $id, threadId: $thread, subject: $subject, from: $from, date: $date, snippet: $snippet, labels: $labels}')
  
  MESSAGES=$(echo "$MESSAGES" | jq --argjson msg "$MSG_OBJ" '. + [$msg]')
  
  COUNT=$((COUNT + 1))
  echo "Fetched $COUNT/$LIMIT..." >&2
  
done <<< "$UNREAD"

# Return JSON report
jq -n \
  --argjson count "$COUNT" \
  --argjson messages "$MESSAGES" \
  --arg profile "$PROFILE" \
  '{profile: $profile, unread: $count, messages: $messages}'
