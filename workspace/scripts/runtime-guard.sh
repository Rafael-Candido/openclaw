#!/usr/bin/env bash
set -euo pipefail

# Shared runtime hardening for cron scripts.
# - Prevents overlapping executions (best-effort lock with stale recovery)
# - Adds structured logs, retries, timeout runner, env guards and runtime metrics.

export LC_ALL="${LC_ALL:-C}"
export TZ="${TZ:-UTC}"

OCW_GUARD_ENABLED="${OCW_GUARD_ENABLED:-true}"
OCW_GUARD_LOG_JSON="${OCW_GUARD_LOG_JSON:-false}"
OCW_GUARD_HEARTBEAT_ENABLED="${OCW_GUARD_HEARTBEAT_ENABLED:-true}"
OCW_GUARD_HEARTBEAT_DIR="${OCW_GUARD_HEARTBEAT_DIR:-/tmp/openclaw-heartbeats}"
OCW_GUARD_LOCK_PREFIX="${OCW_GUARD_LOCK_PREFIX:-/tmp/openclaw-lock-}"

ocw_guard_now_epoch() { date +%s; }
ocw_guard_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ocw_guard_log() {
  local level="${1:-INFO}"
  shift || true
  local msg="${*:-}"
  if [[ "${OCW_GUARD_LOG_JSON}" == "true" ]]; then
    jq -cn --arg ts "$(ocw_guard_now_iso)" --arg lvl "${level}" --arg msg "${msg}" \
      '{ts:$ts,level:$lvl,msg:$msg}'
  else
    printf '[runtime-guard] %s [%s] %s\n' "$(ocw_guard_now_iso)" "${level}" "${msg}"
  fi
}

ocw_guard_safe_int() {
  local raw="${1:-0}"
  local fallback="${2:-0}"
  if [[ "${raw}" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "${raw}"
  else
    printf '%s' "${fallback}"
  fi
}

ocw_guard_clamp_int() {
  local raw="${1:-0}" min="${2:-0}" max="${3:-2147483647}"
  raw="$(ocw_guard_safe_int "${raw}" "${min}")"
  min="$(ocw_guard_safe_int "${min}" 0)"
  max="$(ocw_guard_safe_int "${max}" 2147483647)"
  (( raw < min )) && raw="${min}"
  (( raw > max )) && raw="${max}"
  printf '%s' "${raw}"
}

ocw_guard_require_env() {
  local missing=()
  local key
  for key in "$@"; do
    if [[ -z "${!key:-}" ]]; then
      missing+=("${key}")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    jq -cn --argjson m "$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)" \
      '{ok:false,error:"missing_env",missing_env:$m}'
    return 1
  fi
  return 0
}

ocw_guard_jitter_sleep() {
  local max_sec="${1:-2}"
  max_sec="$(ocw_guard_clamp_int "${max_sec}" 0 60)"
  (( max_sec == 0 )) && return 0
  local rnd=$(( RANDOM % (max_sec + 1) ))
  sleep "${rnd}"
}

ocw_guard_retry() {
  local attempts="${1:-3}"
  local base_delay="${2:-1}"
  shift 2 || true
  attempts="$(ocw_guard_clamp_int "${attempts}" 1 10)"
  base_delay="$(ocw_guard_clamp_int "${base_delay}" 0 30)"
  local i=1 rc=0
  while (( i <= attempts )); do
    "$@" && return 0
    rc=$?
    if (( i < attempts )); then
      local delay=$(( base_delay * i ))
      sleep "$(ocw_guard_clamp_int "${delay}" 0 120)"
    fi
    i=$((i+1))
  done
  return "${rc}"
}

ocw_guard_run_with_timeout() {
  local timeout_sec="${1:-60}"
  shift || true
  timeout_sec="$(ocw_guard_clamp_int "${timeout_sec}" 1 3600)"
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_sec}"s "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_sec}"s "$@"
  else
    "$@"
  fi
}

ocw_guard_mark_start() {
  OCW_GUARD_STARTED_AT="$(ocw_guard_now_epoch)"
}

ocw_guard_mark_end() {
  local end elapsed
  end="$(ocw_guard_now_epoch)"
  elapsed=0
  if [[ -n "${OCW_GUARD_STARTED_AT:-}" ]] && [[ "${OCW_GUARD_STARTED_AT}" =~ ^[0-9]+$ ]]; then
    elapsed=$(( end - OCW_GUARD_STARTED_AT ))
  fi
  printf '%s' "${elapsed}"
}

ocw_guard_touch_heartbeat() {
  local name="${1:-generic}"
  [[ "${OCW_GUARD_HEARTBEAT_ENABLED}" != "true" ]] && return 0
  mkdir -p "${OCW_GUARD_HEARTBEAT_DIR}" 2>/dev/null || true
  printf '{"ts":"%s","epoch":%s}\n' "$(ocw_guard_now_iso)" "$(ocw_guard_now_epoch)" > \
    "${OCW_GUARD_HEARTBEAT_DIR}/${name}.json" 2>/dev/null || true
}

ocw_guard_acquire_lock() {
  local lock_key="${1:?lock_key required}"
  local stale_sec="${2:-1800}"
  [[ "${OCW_GUARD_ENABLED}" != "true" ]] && return 0
  stale_sec="$(ocw_guard_clamp_int "${stale_sec}" 60 86400)"
  local lock_dir="${OCW_GUARD_LOCK_PREFIX}${lock_key}"
  local pid_file="${lock_dir}/pid"
  local ts_file="${lock_dir}/created_at"
  local meta_file="${lock_dir}/meta.json"
  local now existing_pid created_at age

  now="$(ocw_guard_now_epoch)"
  if mkdir "${lock_dir}" 2>/dev/null; then
    printf '%s\n' "$$" > "${pid_file}"
    printf '%s\n' "${now}" > "${ts_file}"
    jq -cn --arg key "${lock_key}" --arg pid "$$" --arg started "$(ocw_guard_now_iso)" \
      --arg cwd "${PWD}" --arg host "${HOSTNAME:-unknown}" \
      '{lock_key:$key,pid:$pid,started_at:$started,cwd:$cwd,host:$host}' > "${meta_file}" 2>/dev/null || true
    OCW_GUARD_LOCK_DIR="${lock_dir}"
    return 0
  fi

  existing_pid="$(cat "${pid_file}" 2>/dev/null || true)"
  created_at="$(cat "${ts_file}" 2>/dev/null || echo 0)"
  age=0
  if [[ "${created_at}" =~ ^[0-9]+$ ]] && (( created_at > 0 )) && (( now >= created_at )); then
    age=$((now - created_at))
  fi

  local pid_alive=0
  if [[ "${existing_pid}" =~ ^[0-9]+$ ]]; then
    if kill -0 "${existing_pid}" 2>/dev/null; then
      pid_alive=1
    elif ps -p "${existing_pid}" >/dev/null 2>&1; then
      # Process exists but may be owned by another user (kill -0 -> EPERM).
      pid_alive=1
    fi
  fi

  # Recover stale/invalid lock.
  if [[ ! "${existing_pid}" =~ ^[0-9]+$ ]] || (( pid_alive == 0 )) || (( age > stale_sec )); then
    rm -rf "${lock_dir}" 2>/dev/null || true
    if mkdir "${lock_dir}" 2>/dev/null; then
      printf '%s\n' "$$" > "${pid_file}"
      printf '%s\n' "${now}" > "${ts_file}"
      jq -cn --arg key "${lock_key}" --arg pid "$$" --arg started "$(ocw_guard_now_iso)" \
        --arg cwd "${PWD}" --arg host "${HOSTNAME:-unknown}" \
        '{lock_key:$key,pid:$pid,started_at:$started,cwd:$cwd,host:$host,recovered:true}' > "${meta_file}" 2>/dev/null || true
      OCW_GUARD_LOCK_DIR="${lock_dir}"
      return 0
    fi
  fi

  OCW_GUARD_LOCK_DIR="${lock_dir}"
  return 1
}

ocw_guard_release_lock() {
  [[ "${OCW_GUARD_ENABLED}" != "true" ]] && return 0
  if [[ -n "${OCW_GUARD_LOCK_DIR:-}" ]]; then
    rm -rf "${OCW_GUARD_LOCK_DIR}" 2>/dev/null || true
  fi
}

ocw_guard_install_traps() {
  trap 'ocw_guard_release_lock' EXIT INT TERM
}
