#!/usr/bin/env bash
# Export Notion page to markdown
set -euo pipefail

PAGE_ID="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "$PAGE_ID" || -z "$OUTPUT_FILE" ]]; then
  echo "Usage: $0 <pageId> <outputFile>" >&2
  exit 1
fi

if [[ -f "/var/www/openclaw/.env" ]]; then
  set -a
  source "/var/www/openclaw/.env"
  set +a
fi

API_KEY="${NOTION_SMARTENVIOS_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
  echo "Missing NOTION_SMARTENVIOS_API_KEY" >&2
  exit 1
fi

# Clean page ID (remove hyphens)
PAGE_ID=$(echo "$PAGE_ID" | tr -d '-')

# Get page metadata
PAGE=$(curl -sS -X GET "https://api.notion.com/v1/pages/$PAGE_ID" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Notion-Version: 2022-06-28")

TITLE=$(echo "$PAGE" | jq -r '.properties.title.title[0].text.content // .properties.Name.title[0].text.content // "Untitled"')

# Get blocks
BLOCKS=$(curl -sS -X GET "https://api.notion.com/v1/blocks/$PAGE_ID/children?page_size=100" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Notion-Version: 2022-06-28")

# Convert to markdown
{
  echo "# $TITLE"
  echo ""
  echo "Source: https://notion.so/$PAGE_ID"
  echo "Exported: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  
  echo "$BLOCKS" | jq -r '.results[] | 
    if .type == "heading_1" then
      "# " + (.heading_1.rich_text[0].text.content // "")
    elif .type == "heading_2" then
      "## " + (.heading_2.rich_text[0].text.content // "")
    elif .type == "heading_3" then
      "### " + (.heading_3.rich_text[0].text.content // "")
    elif .type == "paragraph" then
      (.paragraph.rich_text[0].text.content // "") + "\n"
    elif .type == "bulleted_list_item" then
      "- " + (.bulleted_list_item.rich_text[0].text.content // "")
    elif .type == "numbered_list_item" then
      "1. " + (.numbered_list_item.rich_text[0].text.content // "")
    elif .type == "to_do" then
      "- [" + (if .to_do.checked then "x" else " " end) + "] " + (.to_do.rich_text[0].text.content // "")
    elif .type == "code" then
      "```\n" + (.code.rich_text[0].text.content // "") + "\n```"
    elif .type == "quote" then
      "> " + (.quote.rich_text[0].text.content // "")
    elif .type == "divider" then
      "---"
    else
      ""
    end'
} > "$OUTPUT_FILE"

echo "Exported to: $OUTPUT_FILE" >&2
