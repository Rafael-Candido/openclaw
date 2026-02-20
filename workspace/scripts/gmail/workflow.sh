#!/usr/bin/env bash
# Complete email processing workflow for Mail-Pro/Mail-Person
# Returns actionable data for agent to process

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-100}"

SCRIPTS_DIR="$(dirname "$0")"
TRIAGE_SH="$SCRIPTS_DIR/triage.sh"
ANALYZE_SH="$SCRIPTS_DIR/analyze.sh"

if [[ ! -x "$TRIAGE_SH" || ! -x "$ANALYZE_SH" ]]; then
  echo "Error: required scripts not found" >&2
  exit 1
fi

# Get unread messages
UNREAD=$("$TRIAGE_SH" "$PROFILE" "$LIMIT" 2>/dev/null)
TOTAL=$(echo "$UNREAD" | jq -r '.unread')

if [[ "$TOTAL" == "0" ]]; then
  echo '{"profile": "'"$PROFILE"'", "total": 0, "processed": []}'
  exit 0
fi

# Analyze each message
PROCESSED="[]"
COUNT=0

while IFS= read -r MSG_ID; do
  [[ -z "$MSG_ID" ]] && continue
  
  ANALYSIS=$("$ANALYZE_SH" "$PROFILE" "$MSG_ID" 2>/dev/null)
  
  # Add analysis to processed list
  PROCESSED=$(echo "$PROCESSED" | jq --argjson analysis "$ANALYSIS" '. + [$analysis]')
  
  COUNT=$((COUNT + 1))
  echo "Analyzed $COUNT/$TOTAL..." >&2
  
done < <(echo "$UNREAD" | jq -r '.messages[].id')

# Sort by priority score (descending)
PROCESSED=$(echo "$PROCESSED" | jq 'sort_by(-.priority.score)')

# Build final report
jq -n \
  --arg profile "$PROFILE" \
  --argjson total "$TOTAL" \
  --argjson processed "$PROCESSED" \
  '{
    profile: $profile,
    total: $total,
    processed: $processed,
    summary: {
      needsDraft: ([$processed[] | select(.priority.action == "draft")] | length),
      needsReview: ([$processed[] | select(.priority.action == "review")] | length),
      needsLabel: ([$processed[] | select(.priority.action == "label")] | length),
      shouldIgnore: ([$processed[] | select(.priority.action == "ignore")] | length)
    }
  }'
