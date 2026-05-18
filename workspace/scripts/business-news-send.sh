#!/usr/bin/env bash
# Envia o Business-News para WhatsApp em uma mensagem por noticia.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEWS_SCRIPT="${SCRIPT_DIR}/business-news-simple.sh"
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw || true)}"

if [[ -z "${OPENCLAW_BIN}" && -x "/Users/rafaelcanper/.nvm/versions/node/v22.22.0/bin/openclaw" ]]; then
  OPENCLAW_BIN="/Users/rafaelcanper/.nvm/versions/node/v22.22.0/bin/openclaw"
fi

if [[ -z "${OPENCLAW_BIN}" ]]; then
  echo '{"ok":false,"error":"openclaw binary not found"}'
  exit 1
fi

payload="$("${NEWS_SCRIPT}")"

if [[ "$(jq -r '.whatsapp_ready // false' <<<"${payload}")" != "true" ]]; then
  jq -c '{ok:false,error:"whatsapp_not_ready",status,top_count,errors}' <<<"${payload}"
  exit 1
fi

target="$(jq -r '.whatsapp_number // empty' <<<"${payload}")"
if [[ -z "${target}" ]]; then
  echo '{"ok":false,"error":"whatsapp target missing"}'
  exit 1
fi

tmp_messages="$(mktemp)"
trap 'rm -f "${tmp_messages}"' EXIT
jq -j '.messages[] | . + "\u0000"' <<<"${payload}" > "${tmp_messages}"

sent=0
failures=0
message_ids=()

while IFS= read -r -d '' msg; do
  if [[ -z "${msg}" ]]; then
    continue
  fi

  send_out="$("${OPENCLAW_BIN}" message send \
    --channel whatsapp \
    --target "${target}" \
    --message "${msg}" \
    --json 2>&1)" || {
      failures=$((failures + 1))
      continue
    }

  sent=$((sent + 1))
  message_id="$(jq -r '.payload.result.messageId // empty' <<<"${send_out}" 2>/dev/null || true)"
  if [[ -n "${message_id}" ]]; then
    message_ids+=("${message_id}")
  fi

  sleep "${BUSINESS_NEWS_SEND_DELAY_SEC:-0.4}"
done < "${tmp_messages}"

jq -n \
  --argjson source "${payload}" \
  --arg target "${target}" \
  --argjson sent "${sent}" \
  --argjson failures "${failures}" \
  --argjson messageIds "$(printf '%s\n' "${message_ids[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')" \
  '{
    ok: ($failures == 0 and $sent == ($source.top_count // 0)),
    status: (if $failures == 0 then "sent" else "partial" end),
    target: $target,
    top_count: ($source.top_count // 0),
    sent_count: $sent,
    failure_count: $failures,
    message_mode: ($source.message_mode // "one_message_per_news"),
    message_ids: $messageIds
  }'
