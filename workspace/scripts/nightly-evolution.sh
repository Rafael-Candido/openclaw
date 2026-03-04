#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/workspace/tmp"
mkdir -p "${TMP_DIR}"
RUNTIME_GUARD="${SCRIPT_DIR}/runtime-guard.sh"

PID_FILE="${TMP_DIR}/nightly-evolution.pid"
STATE_FILE="${TMP_DIR}/nightly-evolution.state"
LOG_FILE="${TMP_DIR}/nightly-evolution.log"
LOCK_DIR="${TMP_DIR}/nightly-evolution.lockdir"

MODE="${1:-start}"

LOOP_INTERVAL_SEC="${NIGHTLY_LOOP_INTERVAL_SEC:-45}"
ANALYZE_EVERY_N_LOOPS="${NIGHTLY_ANALYZE_EVERY_N_LOOPS:-4}"
MAX_SELF_HEAL_ATTEMPTS="${NIGHTLY_MAX_SELF_HEAL_ATTEMPTS:-2}"
MAX_LOOPS="${NIGHTLY_MAX_LOOPS:-0}"

guard_bootstrap() {
  if [[ -x "${RUNTIME_GUARD}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNTIME_GUARD}"
    if ! ocw_guard_acquire_lock "nightly-evolution" "${CRON_LOCK_STALE_SEC:-7200}"; then
      echo "nightly-evolution already running (runtime-guard lock)"
      exit 0
    fi
    trap 'ocw_guard_release_lock' EXIT INT TERM
    ocw_guard_mark_start
  fi
}

run_once() {
  local loop_no="$1"
  local run_log="${TMP_DIR}/nightly-loop-${loop_no}-$(date +%Y%m%d-%H%M%S).log"
  local fail_count=0

  {
    echo "=== loop=${loop_no} ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    CRON_SAFE_TIMEOUT_MS="${CRON_SAFE_TIMEOUT_MS:-60000}" \
    CRON_SAFE_GAP_SEC="${CRON_SAFE_GAP_SEC:-1}" \
    CRON_SAFE_COOLDOWN_SEC="${CRON_SAFE_COOLDOWN_SEC:-10}" \
      "${SCRIPT_DIR}/cron-safe-run.sh" --cycles 1
  } | tee -a "${LOG_FILE}" > "${run_log}"

  fail_count="$(grep -E '^cron\|.*\|(error|timeout|gateway-timeout)$' "${run_log}" | wc -l | tr -d ' ' || true)"

  if (( fail_count > 0 )); then
    echo "loop=${loop_no} fail_count=${fail_count} action=self-heal" | tee -a "${LOG_FILE}"
    local i=1
    while (( i <= MAX_SELF_HEAL_ATTEMPTS )); do
      echo "self-heal attempt=${i} loop=${loop_no}" | tee -a "${LOG_FILE}"
      CRON_SAFE_TIMEOUT_MS=70000 \
      CRON_SAFE_GAP_SEC=1 \
      CRON_SAFE_COOLDOWN_SEC=10 \
        "${SCRIPT_DIR}/cron-safe-run.sh" --cycles 1 >> "${LOG_FILE}" 2>&1 || true
      i=$((i + 1))
    done
  fi

  if (( loop_no % ANALYZE_EVERY_N_LOOPS == 0 )); then
    echo "loop=${loop_no} action=analyze-cron-logs" | tee -a "${LOG_FILE}"
    "${SCRIPT_DIR}/analyze-cron-logs.sh" 20 >> "${LOG_FILE}" 2>&1 || true
  fi

  cat > "${STATE_FILE}" <<EOF
loop=${loop_no}
last_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
last_fail_count=${fail_count}
last_run_log=${run_log}
EOF

  if type ocw_guard_touch_heartbeat >/dev/null 2>&1; then
    ocw_guard_touch_heartbeat "nightly-evolution"
  fi
}

start_loop() {
  guard_bootstrap
  if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    echo "nightly-evolution already running"
    exit 0
  fi
  trap 'rm -rf "${LOCK_DIR}" 2>/dev/null || true; type ocw_guard_release_lock >/dev/null 2>&1 && ocw_guard_release_lock 2>/dev/null || true' EXIT INT TERM

  echo "$$" > "${PID_FILE}"
  echo "nightly-evolution started pid=$$" | tee -a "${LOG_FILE}"

  local loop_no=0
  while true; do
    loop_no=$((loop_no + 1))
    run_once "${loop_no}"
    if [[ "${MAX_LOOPS}" =~ ^[0-9]+$ ]] && (( MAX_LOOPS > 0 )) && (( loop_no >= MAX_LOOPS )); then
      echo "nightly-evolution finished max_loops=${MAX_LOOPS}" | tee -a "${LOG_FILE}"
      break
    fi
    sleep "${LOOP_INTERVAL_SEC}"
  done
}

stop_loop() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      sleep 1
      if kill -0 "${pid}" 2>/dev/null; then
        kill -9 "${pid}" 2>/dev/null || true
      fi
      echo "nightly-evolution stopped pid=${pid}"
    else
      echo "nightly-evolution pid file exists but process is not running"
    fi
    rm -f "${PID_FILE}"
  else
    echo "nightly-evolution is not running"
  fi
}

status_loop() {
  local running="false"
  local pid=""
  if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      running="true"
    fi
  fi

  echo "running=${running}"
  echo "pid=${pid}"
  if [[ -f "${STATE_FILE}" ]]; then
    cat "${STATE_FILE}"
  fi
  if type ocw_guard_mark_end >/dev/null 2>&1; then
    echo "runtime_sec=$(ocw_guard_mark_end)"
  fi
  echo "log=${LOG_FILE}"
}

case "${MODE}" in
  start) start_loop ;;
  stop) stop_loop ;;
  status) status_loop ;;
  *)
    echo "usage: $0 {start|stop|status}"
    exit 2
    ;;
esac
