#!/usr/bin/env bash
# Complete email processing workflow for Mail-Pro/Mail-Person
# Returns actionable data for agent to process.
# Otimizado: 1 list + N get (triage) + análise em memória (sem N get + N thread do analyze.sh).

set -euo pipefail

PROFILE="${1:-pro}"
LIMIT="${2:-100}"

SCRIPTS_DIR="$(dirname "$0")"
TRIAGE_SH="$SCRIPTS_DIR/triage.sh"
ANALYZE_FROM_TRIAGE_SH="$SCRIPTS_DIR/analyze-from-triage.sh"

if [[ ! -x "$TRIAGE_SH" || ! -x "$ANALYZE_FROM_TRIAGE_SH" ]]; then
  echo "Error: required scripts not found" >&2
  exit 1
fi

# Uma chamada: list + N get (triage). Sem loop de analyze.sh (evita N get + N thread).
UNREAD=$("$TRIAGE_SH" "$PROFILE" "$LIMIT" 2>/dev/null)
TOTAL=$(echo "$UNREAD" | jq -r '.unread')

if [[ "$TOTAL" == "0" ]]; then
  echo '{"profile": "'"$PROFILE"'", "total": 0, "processed": []}'
  exit 0
fi

# Análise em memória a partir do JSON do triage (zero chamadas Gmail extras)
RESULT=$(echo "$UNREAD" | "$ANALYZE_FROM_TRIAGE_SH" "$PROFILE" 2>/dev/null)

# Garantir formato esperado por process-workflow.sh
echo "$RESULT" | jq -c '{
  profile: .profile,
  total: .total,
  processed: .processed,
  summary: .summary
}'
