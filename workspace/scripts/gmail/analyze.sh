#!/usr/bin/env bash
# Intelligent email analysis for drafting
# Filters auto-replies, prioritizes direct mentions, provides thread context

set -euo pipefail

PROFILE="${1:-pro}"
MSG_ID="${2:-}"

if [[ -z "$MSG_ID" ]]; then
  echo "Usage: $0 <pro|personal> <messageId>" >&2
  exit 1
fi

GMAIL_SH="$(dirname "$0")/gmail.sh"

# Get full message
MSG=$("$GMAIL_SH" "$PROFILE" get "$MSG_ID")

# Extract headers
SUBJECT=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Subject") | .value')
FROM=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "From") | .value')
TO=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "To") | .value')
CC=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Cc") | .value // empty')
DATE=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Date") | .value')
THREAD_ID=$(echo "$MSG" | jq -r '.threadId')
SNIPPET=$(echo "$MSG" | jq -r '.snippet')

# Check for auto-reply indicators
AUTO_SUBMITTED=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Auto-Submitted") | .value // empty')
X_AUTOREPLY=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "X-Autoreply" or .name == "X-Auto-Response-Suppress") | .value // empty')
PRECEDENCE=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Precedence") | .value // empty')

IS_AUTO_REPLY="false"
IS_BULK_MAIL="false"
IS_PROMOTIONAL="false"

# Strong auto-reply indicators
if [[ -n "$AUTO_SUBMITTED" && "$AUTO_SUBMITTED" != "no" ]]; then
  IS_AUTO_REPLY="true"
fi
if [[ "$X_AUTOREPLY" == "yes" ]]; then
  IS_AUTO_REPLY="true"
fi

# Precedence indicators (not always auto-reply, just bulk/list)
if [[ "$PRECEDENCE" == "bulk" || "$PRECEDENCE" == "junk" ]]; then
  IS_BULK_MAIL="true"
fi
if [[ "$PRECEDENCE" == "list" ]]; then
  # List emails are not auto-replies, just group/mailing list
  IS_BULK_MAIL="true"
fi

# Check subject for auto-reply patterns (strict)
if [[ "$SUBJECT" =~ ^(Re:\ )?(Auto|Automatic\ Reply|Out\ of\ Office|Ausência|Fora\ do\ escritório|Delivery\ Status\ Notification|Mail\ Delivery|Undelivered|Returned\ mail|Bounce|failure\ notice) ]]; then
  IS_AUTO_REPLY="true"
fi

# Check for notification patterns
IS_NOTIFICATION="false"
if [[ "$SUBJECT" =~ (notification|notificação|alert|alerta|status|update|atualização|confirmação|confirmation) ]] && \
   [[ "$FROM" =~ (noreply|no-reply|donotreply|do-not-reply|notifications?@|alerts?@|status@) ]]; then
  IS_NOTIFICATION="true"
fi

# Promotional/commercial outreach patterns (avoid drafting by default)
if echo "$SUBJECT $SNIPPET" | grep -qEi "(newsletter|boletim|oferta|promo(ção)?|cupom|desconto|inscreva-se|webinar|evento|convite|agenda|horários|horarios|últimos horários|ultimos horarios|demonstração|demonstracao|vamos conversar|conversar sobre)"; then
  IS_PROMOTIONAL="true"
fi

# Check for direct mention (profile-specific)
EMAIL_TO_CHECK=""
case "$PROFILE" in
  pro)
    EMAIL_TO_CHECK="rafael.pereira@smartenvios.com"
    ;;
  personal)
    EMAIL_TO_CHECK="rafael.silva.pereira10@gmail.com"
    ;;
esac

HAS_DIRECT_MENTION="false"
# Destinatário direto só se Rafael estiver em To:. Em Cc = informativo, não criar draft.
if [[ -n "$TO" && "$TO" == *"$EMAIL_TO_CHECK"* ]]; then
  HAS_DIRECT_MENTION="true"
fi
# Se está apenas em Cc (não em To), nunca draft — é informativo.
if [[ -n "$CC" && "$CC" == *"$EMAIL_TO_CHECK"* && "$TO" != *"$EMAIL_TO_CHECK"* ]]; then
  HAS_DIRECT_MENTION="false"
fi

# Request signal: only draft when there is explicit ask or ongoing actionable thread
HAS_REQUEST_SIGNAL="false"
if echo "$SUBJECT $SNIPPET" | grep -qEi "(pode|poderia|consegue|conseguiria|favor|por favor|preciso|precisamos|pode me|solicito|solicitação|request|need|could you|can you|prazo|deadline|urgente|urgent|\?)"; then
  HAS_REQUEST_SIGNAL="true"
fi

# Get thread history (up to 10 messages)
THREAD=$("$GMAIL_SH" "$PROFILE" thread "$THREAD_ID" 2>/dev/null || echo '{}')
THREAD_SIZE=$(echo "$THREAD" | jq '.messages | length // 0')

# Extract thread context (last 3 messages)
THREAD_CONTEXT="[]"
if [[ $THREAD_SIZE -gt 0 ]]; then
  THREAD_CONTEXT=$(echo "$THREAD" | jq '[.messages[-3:] | .[] | {
    date: (.payload.headers[] | select(.name == "Date") | .value),
    from: (.payload.headers[] | select(.name == "From") | .value),
    subject: (.payload.headers[] | select(.name == "Subject") | .value),
    snippet
  }]')
fi

# Calculate priority score
PRIORITY_SCORE=0

# Base: is it auto-reply? (disqualify completely)
if [[ "$IS_AUTO_REPLY" == "true" ]]; then
  PRIORITY_SCORE=-100
fi

# Notification? (penalize heavily but not disqualify)
if [[ "$IS_NOTIFICATION" == "true" ]]; then
  PRIORITY_SCORE=-50
fi

# Bulk/List mail? (slight penalty)
if [[ "$IS_BULK_MAIL" == "true" ]]; then
  PRIORITY_SCORE=$((PRIORITY_SCORE - 10))
fi

# Positive signals (only if not completely disqualified by auto-reply)
if [[ $PRIORITY_SCORE -gt -100 ]]; then
  # Direct mention: +50
  if [[ "$HAS_DIRECT_MENTION" == "true" ]]; then
    PRIORITY_SCORE=$((PRIORITY_SCORE + 50))
  fi
  
  # Thread depth: +5 per message (up to +25)
  if [[ $THREAD_SIZE -gt 1 ]]; then
    THREAD_BONUS=$((THREAD_SIZE * 5))
    if [[ $THREAD_BONUS -gt 25 ]]; then
      THREAD_BONUS=25
    fi
    PRIORITY_SCORE=$((PRIORITY_SCORE + THREAD_BONUS))
  fi
  
  # Keywords indicating action needed: +20
  if echo "$SUBJECT $SNIPPET" | grep -qEi "(urgente|urgent|ASAP|prazo|deadline|solicito|solicitação|request|preciso|need|favor|ajuda|help|dúvida|duvida|question|problema|issue)"; then
    PRIORITY_SCORE=$((PRIORITY_SCORE + 20))
  fi
  
  # From a known domain (not generic services): +10
  if echo "$FROM" | grep -qEi "@smartenvios\.com|@cliente\.com|@parceiro\.com"; then
    PRIORITY_SCORE=$((PRIORITY_SCORE + 10))
  fi
fi

# Determine action recommendation
ACTION="ignore"
if [[ $PRIORITY_SCORE -ge 50 ]]; then
  ACTION="draft"
elif [[ $PRIORITY_SCORE -ge 20 ]]; then
  ACTION="review"
elif [[ $PRIORITY_SCORE -ge 0 ]]; then
  ACTION="label"
fi

# Never create draft for no-reply / notifications / bulk / or when Rafael is only in Cc (informativo)
if [[ "$ACTION" == "draft" ]]; then
  if [[ "$IS_NOTIFICATION" == "true" ]]; then
    ACTION="label"
  elif [[ "$IS_BULK_MAIL" == "true" ]]; then
    ACTION="label"
  elif [[ "$IS_PROMOTIONAL" == "true" ]]; then
    ACTION="review"
  elif [[ "$HAS_DIRECT_MENTION" != "true" ]]; then
    # Inclui: não está em To; ou está apenas em Cc (informativo) — nunca draft
    ACTION="review"
  elif [[ "$HAS_REQUEST_SIGNAL" != "true" && $THREAD_SIZE -lt 3 ]]; then
    ACTION="review"
  elif echo "$FROM" | grep -qEi "noreply@|no-reply@|donotreply@|do-not-reply@|notifications?@|alerts?@|status@|mailer-daemon@|bounce@"; then
    ACTION="label"
  fi
fi

# Build analysis JSON
jq -n \
  --arg id "$MSG_ID" \
  --arg thread "$THREAD_ID" \
  --arg subject "$SUBJECT" \
  --arg from "$FROM" \
  --arg to "$TO" \
  --arg date "$DATE" \
  --arg snippet "$SNIPPET" \
  --arg auto "$IS_AUTO_REPLY" \
  --arg bulk "$IS_BULK_MAIL" \
  --arg notif "$IS_NOTIFICATION" \
  --arg promo "$IS_PROMOTIONAL" \
  --arg mention "$HAS_DIRECT_MENTION" \
  --arg requestSignal "$HAS_REQUEST_SIGNAL" \
  --argjson score "$PRIORITY_SCORE" \
  --arg action "$ACTION" \
  --argjson threadSize "$THREAD_SIZE" \
  --argjson context "$THREAD_CONTEXT" \
  '{
    messageId: $id,
    threadId: $thread,
    subject: $subject,
    from: $from,
    to: $to,
    date: $date,
    snippet: $snippet,
    flags: {
      isAutoReply: $auto,
      isBulkMail: $bulk,
      isNotification: $notif,
      isPromotional: $promo,
      hasDirectMention: $mention,
      hasRequestSignal: $requestSignal
    },
    priority: {
      score: $score,
      action: $action
    },
    thread: {
      size: $threadSize,
      context: $context
    }
  }'
