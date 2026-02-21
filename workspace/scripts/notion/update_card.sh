#!/usr/bin/env bash
# Update Notion card status and add comment
# Usage: ./update_card.sh <PAGE_ID> <STATUS> [COMMENT]

set -e

PAGE_ID="$1"
STATUS="$2"
COMMENT="${3:-}"

if [[ -z "$PAGE_ID" || -z "$STATUS" ]]; then
    echo "Usage: $0 <PAGE_ID> <STATUS> [COMMENT]"
    exit 1
fi

API_KEY="${NOTION_SMARTENVIOS_API_KEY}"

if [[ -z "$API_KEY" ]]; then
    echo "Error: NOTION_SMARTENVIOS_API_KEY not set."
    exit 1
fi
HELPER_SCRIPT="/var/www/openclaw/workspace/scripts/notion-helper.sh"

if [[ ! -f "$HELPER_SCRIPT" ]]; then
    echo "Error: notion-helper.sh not found at $HELPER_SCRIPT"
    exit 1
fi

retry_cmd() {
    local max_retries=3
    local delay=2
    local attempt=0
    local cmd=("$@")

    while [[ $attempt -lt $max_retries ]]; do
        if "${cmd[@]}"; then
            return 0
        fi
        echo "Command failed. Retrying in ${delay}s... (Attempt $((attempt + 1))/$max_retries)"
        sleep $delay
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    echo "Error: Command failed after $max_retries attempts."
    return 1
}

# Update status
echo "Updating status to '$STATUS'..."
retry_cmd "$HELPER_SCRIPT" update-status "$PAGE_ID" "$API_KEY" "$STATUS"

# Add comment if provided
if [[ -n "$COMMENT" ]]; then
    echo "Adding comment..."
    retry_cmd "$HELPER_SCRIPT" comment "$PAGE_ID" "$API_KEY" "$COMMENT" "Mail-Pro System"
fi

echo "Success."
