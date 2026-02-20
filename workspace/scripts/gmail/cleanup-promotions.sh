#!/usr/bin/env bash
# Auto-cleanup promotional/social emails with unsubscribe
# Processes emails in CATEGORY_PROMOTIONS and CATEGORY_SOCIAL

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-20}"
DRY_RUN="${3:-false}"

GMAIL_SH="$(dirname "$0")/gmail.sh"
UNSUB_SH="$(dirname "$0")/unsubscribe.sh"

echo "Cleanup mode: $([[ "$DRY_RUN" == "true" ]] && echo "DRY-RUN (detect only)" || echo "ACTIVE (unsubscribe)")" >&2

# Get promotional emails
PROMO=$("$GMAIL_SH" "$PROFILE" list "category:promotions OR category:social" | jq -r ".messages[0:$LIMIT] | .[] | .id" 2>/dev/null || echo "")

if [[ -z "$PROMO" ]]; then
  echo '{"processed": 0, "unsubscribed": 0, "failed": 0}'
  exit 0
fi

PROCESSED=0
UNSUBSCRIBED=0
FAILED=0
RESULTS="[]"

while IFS= read -r MSG_ID; do
  [[ -z "$MSG_ID" ]] && continue
  
  # Check if can unsubscribe
  UNSUB_RESULT=$("$UNSUB_SH" "$PROFILE" "$MSG_ID" "$DRY_RUN" 2>/dev/null)
  
  CAN_UNSUB=$(echo "$UNSUB_RESULT" | jq -r '.canUnsubscribe')
  IS_PROMO=$(echo "$UNSUB_RESULT" | jq -r '.isPromotional')
  EXECUTED=$(echo "$UNSUB_RESULT" | jq -r '.unsubscribeExecuted // false')
  
  if [[ "$IS_PROMO" == "true" && "$CAN_UNSUB" == "true" ]]; then
    if [[ "$EXECUTED" == "true" ]]; then
      UNSUBSCRIBED=$((UNSUBSCRIBED + 1))
      
      # Archive the email after unsubscribe
      if [[ "$DRY_RUN" == "false" ]]; then
        "$GMAIL_SH" "$PROFILE" archive "$MSG_ID" >/dev/null 2>&1
      fi
    else
      FAILED=$((FAILED + 1))
    fi
    
    RESULTS=$(echo "$RESULTS" | jq --argjson unsub "$UNSUB_RESULT" '. + [$unsub]')
  fi
  
  PROCESSED=$((PROCESSED + 1))
  echo "Processed $PROCESSED/$LIMIT..." >&2
  
done <<< "$PROMO"

# Build final report
jq -n \
  --arg profile "$PROFILE" \
  --argjson processed "$PROCESSED" \
  --argjson unsubscribed "$UNSUBSCRIBED" \
  --argjson failed "$FAILED" \
  --argjson dryRun "$([[ "$DRY_RUN" == "true" ]] && echo "true" || echo "false")" \
  --argjson results "$RESULTS" \
  '{
    profile: $profile,
    processed: $processed,
    unsubscribed: $unsubscribed,
    failed: $failed,
    dryRun: $dryRun,
    details: $results
  }'
