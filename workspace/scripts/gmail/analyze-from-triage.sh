#!/usr/bin/env bash
# Análise a partir do JSON do triage (sem chamadas Gmail: sem get nem thread).
# Entrada: stdout de triage.sh (JSON com .messages[]).
# Saída: mesmo formato que analyze.sh (processed list com priority.action, etc.).
# Reduz N get + N thread para zero chamadas extras no workflow.

set -euo pipefail

PROFILE="${1:-pro}"
SCRIPTS_DIR="$(dirname "$0")"
GMAIL_SH="${SCRIPTS_DIR}/gmail.sh"

case "$PROFILE" in
  pro)   EMAIL_TO_CHECK="rafael.pereira@smartenvios.com" ;;
  personal) EMAIL_TO_CHECK="rafael.silva.pereira10@gmail.com" ;;
  *)     echo '{"error":"profile"}' >&2; exit 1 ;;
esac

TRIAGE_JSON="$(cat)"
TOTAL="$(echo "$TRIAGE_JSON" | jq -r '.unread // 0')"
if [[ "$TOTAL" == "0" ]]; then
  echo '{"profile":"'"$PROFILE"'","total":0,"processed":[],"summary":{"needsDraft":0,"needsReview":0,"needsLabel":0,"shouldIgnore":0}}'
  exit 0
fi

# Para cada mensagem do triage, calcular action/score em memória (sem thread)
OUTPUT="$(echo "$TRIAGE_JSON" | jq -c --arg profile "$PROFILE" --arg to_check "$EMAIL_TO_CHECK" '
  .unread as $total
  | [.messages[]?
    | . as $m
    | ($m.snippet // "") as $snippet
    | ($m.subject // "") as $subject
    | ($m.from // "") as $from
    | ($m.to // "") as $to
    | ($m.cc // "") as $cc
    | ($m.autoSubmitted // "") as $auto
    | ($m.precedence // "") as $prec
    | ($m.xAutorreply // "") as $xauto
    | (if ($auto != "" and $auto != "no") or $xauto == "yes" then true else false end) as $is_auto_reply
    | (if $prec == "bulk" or $prec == "junk" or $prec == "list" then true else false end) as $is_bulk
    | (if ($subject | test("notification|notificação|alert|alerta|status|update|atualização|confirmação|confirmation"; "i"))
          and ($from | test("noreply|no-reply|donotreply|notifications?@|alerts?@|status@"; "i")) then true else false end) as $is_notification
    | (if (($subject + " " + $snippet) | test("newsletter|boletim|oferta|promo|cupom|desconto|inscreva-se|webinar|evento|convite"; "i")) then true else false end) as $is_promotional
    | ($to | index($to_check) != null) as $has_direct_mention
    | (if ($cc | index($to_check) != null) then true else false end) as $in_cc
    | (if $has_direct_mention and ($cc == "" or ($to | index($to_check) != null)) then true else false end) as $direct_mention
    | (if ($subject + " " + $snippet) | test("pode|poderia|consegue|favor|preciso|solicito|request|need|could you|can you|prazo|deadline|urgente|\\?"; "i") then true else false end) as $has_request_signal
    | (if $is_auto_reply then -100
       elif $is_notification then -50
       elif $is_bulk then -10
       else 0 end) as $base
    | (if $base > -100 then
         (if $direct_mention then 50 else 0 end) +
         (if ($subject + " " + $snippet) | test("urgente|ASAP|prazo|deadline|solicito|request|preciso|favor|ajuda|dúvida|problema"; "i") then 20 else 0 end) +
         (if $from | test("@smartenvios\\.com|@cliente\\.com|@parceiro\\.com"; "i") then 10 else 0 end)
       else $base end) as $score
    | (if $score >= 50 then "draft"
       elif $score >= 20 then "review"
       elif $score >= 0 then "label"
       else "ignore" end) as $action
    | (if $action == "draft" then
         if $is_notification or $is_bulk or $is_promotional then "label"
         elif ($direct_mention | not) then "review"
         elif ($has_request_signal | not) then "review"
         elif $from | test("noreply@|no-reply@|donotreply@|notifications?@|alerts?@|status@|mailer-daemon@|bounce@"; "i") then "label"
         else "draft" end
       else $action end) as $final_action
    | {
        messageId: $m.id,
        threadId: $m.threadId,
        subject: $subject,
        from: $from,
        to: $to,
        date: ($m.date // ""),
        snippet: $snippet,
        flags: { isAutoReply: $is_auto_reply, isBulkMail: $is_bulk, isNotification: $is_notification, isPromotional: $is_promotional, hasDirectMention: $direct_mention, hasRequestSignal: $has_request_signal },
        priority: { score: $score, action: $final_action },
        thread: { size: 0, context: [] }
      }
  ]
  | sort_by(-.priority.score)
  | {
      profile: $profile,
      total: $total,
      processed: .,
      summary: {
        needsDraft: ([.[] | select(.priority.action == "draft")] | length),
        needsReview: ([.[] | select(.priority.action == "review")] | length),
        needsLabel: ([.[] | select(.priority.action == "label")] | length),
        shouldIgnore: ([.[] | select(.priority.action == "ignore")] | length)
      }
    }
')"

# Garantir total do triage
TOTAL="$(echo "$TRIAGE_JSON" | jq -r '.unread // 0')"
echo "$OUTPUT" | jq --argjson total "$TOTAL" '.total = $total'
