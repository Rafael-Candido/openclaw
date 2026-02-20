#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/www/openclaw/workspace"
CHECK_SCRIPT="$ROOT/scripts/check-logging.sh"

echo "========================================"
echo " OpenClaw Ops Dashboard (quick check)"
echo "========================================"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo

echo "[1/4] Cron jobs (status)"
if openclaw cron list; then
  echo "✅ cron list ok"
else
  echo "❌ cron list failed"
fi

echo
echo "[2/4] Gateway status"
if openclaw gateway status; then
  echo "✅ gateway status ok"
else
  echo "❌ gateway status failed"
fi

echo
echo "[3/4] Logging policy local check"
if [[ -x "$CHECK_SCRIPT" ]]; then
  if "$CHECK_SCRIPT" "$ROOT"; then
    echo "✅ logging policy check ok"
  else
    echo "❌ logging policy check failed"
  fi
else
  echo "⚠️ check script not found/executable: $CHECK_SCRIPT"
fi

echo
echo "[4/4] Last 20 lines of gateway.log"
LOG_FILE="/var/www/openclaw/logs/gateway.log"
if [[ -f "$LOG_FILE" ]]; then
  tail -n 20 "$LOG_FILE" || true
  echo "✅ log tail shown"
else
  echo "⚠️ log file not found: $LOG_FILE"
fi

echo
echo "Done. For live monitoring: openclaw logs --follow"
