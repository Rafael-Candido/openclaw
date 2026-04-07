#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${OPENCLAW_CONFIG_DIR:-/private/var/www/openclaw}"
RETENTION_DAYS="${1:-${OPENCLAW_LOG_RETENTION_DAYS:-2}}"
GATEWAY_LOG_MAX_MB="${OPENCLAW_GATEWAY_LOG_MAX_MB:-50}"
GATEWAY_ERR_LOG_MAX_MB="${OPENCLAW_GATEWAY_ERR_LOG_MAX_MB:-20}"

if ! [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
  echo "retention_days invalido: ${RETENTION_DAYS}" >&2
  exit 1
fi

if ! [[ "${GATEWAY_LOG_MAX_MB}" =~ ^[0-9]+$ ]] || ! [[ "${GATEWAY_ERR_LOG_MAX_MB}" =~ ^[0-9]+$ ]]; then
  echo "gateway_log_max_mb invalido" >&2
  exit 1
fi

deleted_count=0
rotated_count=0

prune_glob() {
  local base_dir="$1"
  local pattern="$2"

  [[ -d "${base_dir}" ]] || return 0

  while IFS= read -r file; do
    rm -f "${file}" || true
    deleted_count=$((deleted_count + 1))
  done < <(find "${base_dir}" -type f -name "${pattern}" -mtime "+${RETENTION_DAYS}" -print 2>/dev/null)
}

rotate_active_log_if_needed() {
  local file="$1"
  local max_mb="$2"
  local size_bytes max_bytes stamp rotated

  [[ -f "${file}" ]] || return 0

  size_bytes="$(wc -c < "${file}" 2>/dev/null | tr -d '[:space:]')"
  [[ "${size_bytes}" =~ ^[0-9]+$ ]] || size_bytes=0
  max_bytes=$((max_mb * 1024 * 1024))
  (( max_bytes > 0 )) || return 0

  if (( size_bytes <= max_bytes )); then
    return 0
  fi

  stamp="$(date +%Y%m%d-%H%M%S)"
  rotated="${file}.${stamp}.bak"
  cp "${file}" "${rotated}" 2>/dev/null || return 0
  : > "${file}"
  gzip -f "${rotated}" >/dev/null 2>&1 || true
  rotated_count=$((rotated_count + 1))
}

prune_rotated_logs() {
  local file="$1"
  local base_dir base_name

  [[ -f "${file}" ]] || return 0
  base_dir="$(dirname "${file}")"
  base_name="$(basename "${file}")"

  while IFS= read -r old_file; do
    rm -f "${old_file}" || true
    deleted_count=$((deleted_count + 1))
  done < <(find "${base_dir}" -type f -name "${base_name}.*.bak*" -mtime "+${RETENTION_DAYS}" -print 2>/dev/null)
}

prune_glob "${ROOT_DIR}/workspace/tmp" "cron-logs-summary-*.json"
prune_glob "${ROOT_DIR}/workspace/tmp" "cron-20rounds-*.summary.json"
prune_glob "${ROOT_DIR}/workspace/tmp" "cron-20rounds-*.summary.txt"
prune_glob "${ROOT_DIR}/workspace/tmp" "cron-20rounds-*.log"
prune_glob "${ROOT_DIR}/workspace/tmp" "ecosystem-smoke-*.json"
prune_glob "${ROOT_DIR}/workspace/tmp" "governance-min-body-*.md"
prune_glob "${ROOT_DIR}/workspace/tmp" "nightly-evolution*.log"

prune_glob "${ROOT_DIR}/workspace/reports" "mcp-audit-*.md"
prune_glob "${ROOT_DIR}/workspace/reports" "stability-cycle-*.md"
prune_glob "${ROOT_DIR}/workspace/reports" "stability-cycle-*.json"

prune_glob "${ROOT_DIR}/cron/runs" "*.jsonl"

rotate_active_log_if_needed "${ROOT_DIR}/logs/gateway.log" "${GATEWAY_LOG_MAX_MB}"
rotate_active_log_if_needed "${ROOT_DIR}/logs/gateway.err.log" "${GATEWAY_ERR_LOG_MAX_MB}"
prune_rotated_logs "${ROOT_DIR}/logs/gateway.log"
prune_rotated_logs "${ROOT_DIR}/logs/gateway.err.log"

echo "pruned_runtime_artifacts=${deleted_count} rotated_active_logs=${rotated_count} retention_days=${RETENTION_DAYS}"
