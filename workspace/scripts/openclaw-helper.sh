#!/usr/bin/env bash
set -euo pipefail

# openclaw-helper.sh
# Small resilience layer around the OpenClaw CLI for automation scripts (Governanca/Otimizador).
#
# Goals:
# - Retry transient gateway errors (restart, 1012, timeouts).
# - Provide higher-level helpers for cron run/wake/enable/disable and session reset.
#
# This file is intended to be sourced by other scripts.

OCW_MAX_RETRIES="${OCW_MAX_RETRIES:-5}"
OCW_BASE_DELAY_SEC="${OCW_BASE_DELAY_SEC:-2}"
OCW_MAX_DELAY_SEC="${OCW_MAX_DELAY_SEC:-15}"
OCW_GATEWAY_HEALTH_TIMEOUT_MS="${OCW_GATEWAY_HEALTH_TIMEOUT_MS:-5000}"

ocw_log() {
  echo "[openclaw-helper] $*" >&2
}

ocw_is_transient_gateway_error() {
  local msg="${1:-}"
  echo "${msg}" | grep -Eqi \
    "gateway timeout|gateway closed|service restart|ECONNREFUSED|EPIPE|Bad request|WebSocket.*closed|connect ECONNREFUSED"
}

ocw_retry() {
  # Usage: ocw_retry <cmd...>
  local -a cmd=( "$@" )
  local attempt=1
  local delay="${OCW_BASE_DELAY_SEC}"
  local out=""
  local ec=0

  while true; do
    out="$("${cmd[@]}" 2>&1)" && { printf "%s" "${out}"; return 0; }
    ec=$?
    if (( attempt >= OCW_MAX_RETRIES )); then
      ocw_log "command failed after ${attempt} attempt(s): ${cmd[*]}"
      printf "%s" "${out}" >&2
      return "${ec}"
    fi
    if ! ocw_is_transient_gateway_error "${out}"; then
      printf "%s" "${out}" >&2
      return "${ec}"
    fi
    ocw_log "transient error (attempt ${attempt}/${OCW_MAX_RETRIES}) for: ${cmd[*]}"
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
    if (( delay > OCW_MAX_DELAY_SEC )); then
      delay="${OCW_MAX_DELAY_SEC}"
    fi
  done
}

ocw_gateway_health() {
  ocw_retry openclaw health --timeout "${OCW_GATEWAY_HEALTH_TIMEOUT_MS}" >/dev/null
}

ocw_gateway_restart() {
  # Best-effort restart, used by governance.
  openclaw gateway stop >/dev/null 2>&1 || true
  sleep 2
  openclaw gateway install --force >/dev/null 2>&1 || openclaw gateway install >/dev/null 2>&1 || true
  sleep 3
  ocw_gateway_health
}

ocw_cron_run() {
  # Usage: ocw_cron_run <cron_id> [timeout_ms]
  local cron_id="${1:?cron id required}"
  local timeout_ms="${2:-30000}"
  ocw_retry openclaw cron run "${cron_id}" --timeout "${timeout_ms}" >/dev/null
}

ocw_cron_wake_now() {
  # Usage: ocw_cron_wake_now <cron_id> [timeout_ms]
  local cron_id="${1:?cron id required}"
  local timeout_ms="${2:-30000}"
  ocw_retry openclaw cron edit "${cron_id}" --wake now --timeout "${timeout_ms}" >/dev/null
}

ocw_cron_enable() {
  local cron_id="${1:?cron id required}"
  ocw_retry openclaw cron edit "${cron_id}" --enable >/dev/null
}

ocw_cron_disable() {
  local cron_id="${1:?cron id required}"
  ocw_retry openclaw cron edit "${cron_id}" --disable >/dev/null
}

ocw_sessions_reset() {
  # Usage: ocw_sessions_reset <session_key>
  local session_key="${1:?session key required}"
  ocw_retry openclaw sessions reset "${session_key}" --yes >/dev/null
}

ocw_cron_list_json() {
  # Usage: ocw_cron_list_json [timeout_sec]
  # `openclaw cron list --json` sometimes hangs; run it under a hard subprocess timeout.
  local timeout_sec="${1:-12}"
  python3 - "${timeout_sec}" <<'PY'
import subprocess, sys
timeout = float(sys.argv[1])
try:
    p = subprocess.run(
        ["openclaw", "cron", "list", "--json"],
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if p.returncode != 0:
        sys.stderr.write(p.stderr or "")
        sys.exit(p.returncode)
    sys.stdout.write(p.stdout or "")
except subprocess.TimeoutExpired:
    sys.stderr.write("ocw_cron_list_json: timeout\n")
    sys.exit(124)
PY
}
