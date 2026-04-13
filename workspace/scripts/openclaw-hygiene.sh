#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT="${OPENCLAW_CONFIG_DIR:-${PROJECT_ROOT}}"
ROOT="$(cd "${ROOT}" && pwd)"

APPLY=false
JSON=false
BACKUP_ONLY=false
GENERATED_ONLY=false
PURGE_HISTORY=false
SKIP_BACKUP=false
ONCE_DAILY=false

KEEP_SESSIONS_PER_AGENT="${OPENCLAW_SESSION_KEEP_FILES:-20}"
MAX_CRON_LINES="${OPENCLAW_CRON_RUN_MAX_LINES:-500}"
GATEWAY_LOG_MAX_MB="${OPENCLAW_GATEWAY_LOG_MAX_MB:-20}"
GATEWAY_ERR_LOG_MAX_MB="${OPENCLAW_GATEWAY_ERR_LOG_MAX_MB:-10}"

usage() {
  cat <<'EOF'
Usage: openclaw-hygiene.sh [--dry-run|--apply] [--json]
                           [--backup-only|--generated-only|--purge-history]
                           [--skip-backup] [--once-daily]

Defaults to --dry-run. Runtime cleanup keeps only one daily backup, caps logs
and cron runs, and prunes generated reports/sessions without moving runtime dirs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --dry-run) APPLY=false ;;
    --json) JSON=true ;;
    --backup-only) BACKUP_ONLY=true ;;
    --generated-only) GENERATED_ONLY=true ;;
    --purge-history) PURGE_HISTORY=true ;;
    --skip-backup) SKIP_BACKUP=true ;;
    --once-daily) ONCE_DAILY=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
is_uint "${KEEP_SESSIONS_PER_AGENT}" || KEEP_SESSIONS_PER_AGENT=20
is_uint "${MAX_CRON_LINES}" || MAX_CRON_LINES=500
is_uint "${GATEWAY_LOG_MAX_MB}" || GATEWAY_LOG_MAX_MB=20
is_uint "${GATEWAY_ERR_LOG_MAX_MB}" || GATEWAY_ERR_LOG_MAX_MB=10

deleted_paths=0
would_delete_paths=0
truncated_files=0
would_truncate_files=0
capped_logs=0
would_cap_logs=0
backup_created=false
backup_would_create=false
skipped_once_daily=false

if [[ -f "${SCRIPT_DIR}/runtime-guard.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/runtime-guard.sh"
  if ! ocw_guard_acquire_lock "openclaw-hygiene" "3600"; then
    if [[ "${JSON}" == "true" ]]; then
      jq -cn '{ok:true,action:"skipped_already_running",lock:"openclaw-hygiene"}'
    else
      echo "openclaw-hygiene: skipped_already_running"
    fi
    exit 0
  fi
  trap 'ocw_guard_release_lock' EXIT
fi

cd "${ROOT}"

today_utc="$(date -u +%Y-%m-%d)"
state_dir="${ROOT}/.cache"
once_marker="${state_dir}/openclaw-hygiene-last-run"

if [[ "${ONCE_DAILY}" == "true" && "${APPLY}" == "true" ]]; then
  last_run="$(cat "${once_marker}" 2>/dev/null || true)"
  if [[ "${last_run}" == "${today_utc}" ]]; then
    skipped_once_daily=true
  fi
fi

safe_delete_path() {
  local path="$1"
  [[ -n "${path}" && "${path}" != "/" && "${path}" != "." && "${path}" != "${ROOT}" ]] || return 0
  [[ -e "${path}" || -L "${path}" ]] || return 0

  if [[ "${APPLY}" == "true" ]]; then
    rm -rf -- "${path}"
    deleted_paths=$((deleted_paths + 1))
  else
    would_delete_paths=$((would_delete_paths + 1))
  fi
}

copy_rel_to_stage() {
  local rel="$1"
  local stage="$2"
  [[ -f "${rel}" ]] || return 0
  mkdir -p "${stage}/$(dirname "${rel}")"
  cp -p "${rel}" "${stage}/${rel}" 2>/dev/null || true
}

write_inventory() {
  local stage="$1"
  {
    echo "created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "root=${ROOT}"
    echo
    echo "[du]"
    du -sh backups logs agents/*/sessions cron/runs workspace/reports workspace/tmp media/inbound tasks flows delivery-queue 2>/dev/null || true
    echo
    echo "[runtime_files]"
    find backups logs agents cron/runs workspace/reports workspace/tmp media delivery-queue tasks flows \
      -type f 2>/dev/null | sed 's#^\./##' | wc -l | tr -d ' '
    echo
    echo "[git_status]"
    git status --short 2>/dev/null || true
  } > "${stage}/RUNTIME-INVENTORY.txt"
}

create_daily_backup() {
  if [[ "${SKIP_BACKUP}" == "true" || "${GENERATED_ONLY}" == "true" ]]; then
    return 0
  fi

  if [[ "${APPLY}" != "true" ]]; then
    backup_would_create=true
    return 0
  fi

  local backup_dir="${ROOT}/backups/daily"
  local stage tmp_tar manifest
  stage="$(mktemp -d /tmp/openclaw-hygiene-backup.XXXXXX)"
  tmp_tar="$(mktemp /tmp/openclaw-latest.XXXXXX.tar.gz)"
  manifest="${backup_dir}/openclaw-latest.manifest.json"

  mkdir -p "${backup_dir}"
  rm -f "${backup_dir}/openclaw-latest.tar.gz" "${manifest}" 2>/dev/null || true

  copy_rel_to_stage ".gitignore" "${stage}"
  copy_rel_to_stage ".env" "${stage}"
  copy_rel_to_stage "openclaw.json" "${stage}"
  copy_rel_to_stage "cron/jobs.json" "${stage}"
  copy_rel_to_stage "workspace/AGENTS.md" "${stage}"
  copy_rel_to_stage "workspace/FLUXO_AGENTES.md" "${stage}"
  copy_rel_to_stage "workspace/TOOLS.md" "${stage}"
  copy_rel_to_stage "workspace/docs/OPENCLAW-OPERATING-CONTRACT.json" "${stage}"
  copy_rel_to_stage "workspace/docs/OPENCLAW-OPERATING-CONTRACT.md" "${stage}"
  copy_rel_to_stage "workspace/docs/REPO-HYGIENE.md" "${stage}"
  copy_rel_to_stage "workspace/templates/agent-behavior-patterns.md" "${stage}"

  while IFS= read -r sdir; do
    find "${sdir}" -maxdepth 1 -type f -name '*.jsonl' -print0 2>/dev/null \
      | xargs -0 ls -1t 2>/dev/null \
      | head -n "${KEEP_SESSIONS_PER_AGENT}" \
      | while IFS= read -r session_file; do
          copy_rel_to_stage "${session_file}" "${stage}"
        done
  done < <(find agents -type d -name sessions 2>/dev/null | sort)

  write_inventory "${stage}"
  tar -C "${stage}" -czf "${tmp_tar}" .
  mv "${tmp_tar}" "${backup_dir}/openclaw-latest.tar.gz"
  jq -cn \
    --arg createdAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg policy "single-daily-backup" \
    --arg path "backups/daily/openclaw-latest.tar.gz" \
    --argjson keepSessions "${KEEP_SESSIONS_PER_AGENT}" \
    '{createdAt:$createdAt,policy:$policy,path:$path,keepSessionsPerAgent:$keepSessions}' > "${manifest}"
  rm -rf "${stage}" 2>/dev/null || true
  backup_created=true
}

clean_backups() {
  [[ "${BACKUP_ONLY}" == "true" || "${GENERATED_ONLY}" == "true" ]] && return 0
  [[ -d backups ]] || return 0

  while IFS= read -r path; do
    safe_delete_path "${path}"
  done < <(find backups -mindepth 1 -maxdepth 1 ! -name daily -print 2>/dev/null)

  if [[ -d backups/daily ]]; then
    while IFS= read -r path; do
      safe_delete_path "${path}"
    done < <(find backups/daily -mindepth 1 -maxdepth 1 \
      ! -name openclaw-latest.tar.gz \
      ! -name openclaw-latest.manifest.json \
      -print 2>/dev/null)
  fi
}

clean_config_backups() {
  [[ "${BACKUP_ONLY}" == "true" || "${GENERATED_ONLY}" == "true" ]] && return 0

  while IFS= read -r file; do
    safe_delete_path "${file}"
  done < <(find cron -maxdepth 1 -type f \( -name '*.bak*' -o -name '*.backup*' -o -name '*.broken' \) -print 2>/dev/null)

  while IFS= read -r file; do
    safe_delete_path "${file}"
  done < <(find . -maxdepth 1 -type f \( -name 'openclaw.json*.bak*' -o -name 'openclaw.json*.backup*' \) -print 2>/dev/null)
}

clean_sessions() {
  [[ "${BACKUP_ONLY}" == "true" || "${GENERATED_ONLY}" == "true" ]] && return 0
  [[ -d agents ]] || return 0

  while IFS= read -r sdir; do
    if [[ "${PURGE_HISTORY}" == "true" ]]; then
      while IFS= read -r file; do
        safe_delete_path "${file}"
      done < <(find "${sdir}" -type f \( -name '*.jsonl' -o -name '*.jsonl.*' -o -name '*.lock' -o -name '*.bak*' -o -name 'sessions.json' \) -print 2>/dev/null)
      continue
    fi

    while IFS= read -r file; do
      safe_delete_path "${file}"
    done < <(find "${sdir}" -type f \( -name '*.jsonl.deleted.*' -o -name '*.jsonl.reset.*' -o -name '*.jsonl.bak*' -o -name '*.bak*' -o -name '*.lock' \) -mtime +1 -print 2>/dev/null)

    count="$(find "${sdir}" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
    if is_uint "${count}" && (( count > KEEP_SESSIONS_PER_AGENT )); then
      remove_n=$((count - KEEP_SESSIONS_PER_AGENT))
      find "${sdir}" -maxdepth 1 -type f -name '*.jsonl' -print0 2>/dev/null \
        | xargs -0 ls -1t 2>/dev/null \
        | tail -n "${remove_n}" \
        | while IFS= read -r file; do safe_delete_path "${file}"; done
    fi
  done < <(find agents -type d -name sessions 2>/dev/null | sort)
}

cap_cron_runs() {
  [[ "${BACKUP_ONLY}" == "true" ]] && return 0
  [[ -d cron/runs ]] || return 0

  if [[ "${PURGE_HISTORY}" == "true" ]]; then
    while IFS= read -r file; do
      safe_delete_path "${file}"
    done < <(find cron/runs -type f -name '*.jsonl' -print 2>/dev/null)
    return 0
  fi

  while IFS= read -r file; do
    lines="$(wc -l < "${file}" 2>/dev/null | tr -d ' ')"
    is_uint "${lines}" || lines=0
    if (( lines > MAX_CRON_LINES )); then
      if [[ "${APPLY}" == "true" ]]; then
        tmp="$(mktemp /tmp/openclaw-cron-run.XXXXXX)"
        tail -n "${MAX_CRON_LINES}" "${file}" > "${tmp}" 2>/dev/null || true
        cat "${tmp}" > "${file}"
        rm -f "${tmp}" 2>/dev/null || true
        truncated_files=$((truncated_files + 1))
      else
        would_truncate_files=$((would_truncate_files + 1))
      fi
    fi
  done < <(find cron/runs -type f -name '*.jsonl' -print 2>/dev/null)
}

cap_log_file() {
  local file="$1"
  local max_mb="$2"
  [[ -f "${file}" ]] || return 0
  local max_bytes size_bytes tmp
  max_bytes=$((max_mb * 1024 * 1024))
  size_bytes="$(wc -c < "${file}" 2>/dev/null | tr -d ' ')"
  is_uint "${size_bytes}" || size_bytes=0
  if (( size_bytes > max_bytes )); then
    if [[ "${APPLY}" == "true" ]]; then
      tmp="$(mktemp /tmp/openclaw-log.XXXXXX)"
      tail -c "${max_bytes}" "${file}" > "${tmp}" 2>/dev/null || true
      cat "${tmp}" > "${file}"
      rm -f "${tmp}" 2>/dev/null || true
      capped_logs=$((capped_logs + 1))
    else
      would_cap_logs=$((would_cap_logs + 1))
    fi
  fi
}

cap_logs() {
  [[ "${BACKUP_ONLY}" == "true" ]] && return 0
  cap_log_file "logs/gateway.log" "${GATEWAY_LOG_MAX_MB}"
  cap_log_file "logs/gateway.err.log" "${GATEWAY_ERR_LOG_MAX_MB}"
  while IFS= read -r file; do
    safe_delete_path "${file}"
  done < <(find logs -type f -name '*.bak*' -print 2>/dev/null)
}

clean_generated_dirs() {
  [[ "${BACKUP_ONLY}" == "true" ]] && return 0
  local dir
  for dir in workspace/tmp workspace/reports; do
    [[ -d "${dir}" ]] || continue
    if [[ "${PURGE_HISTORY}" == "true" ]]; then
      while IFS= read -r file; do
        safe_delete_path "${file}"
      done < <(find "${dir}" -type f -print 2>/dev/null)
    else
      while IFS= read -r file; do
        safe_delete_path "${file}"
      done < <(find "${dir}" -type f ! -mtime -1 -print 2>/dev/null)
    fi
  done
}

clean_media_and_queue() {
  [[ "${BACKUP_ONLY}" == "true" || "${GENERATED_ONLY}" == "true" ]] && return 0
  while IFS= read -r file; do
    safe_delete_path "${file}"
  done < <(find delivery-queue -type f ! -mtime -1 -print 2>/dev/null)
  while IFS= read -r file; do
    base="$(basename "${file}")"
    if rg -q --fixed-strings "${base}" agents/*/sessions/*.jsonl 2>/dev/null; then
      continue
    fi
    safe_delete_path "${file}"
  done < <(find media/inbound -type f ! -mtime -1 -print 2>/dev/null)
}

clean_caches() {
  [[ "${BACKUP_ONLY}" == "true" || "${GENERATED_ONLY}" == "true" ]] && return 0
  safe_delete_path ".pycache"
  safe_delete_path ".ruff_cache"
  while IFS= read -r file; do
    safe_delete_path "${file}"
  done < <(find .cache -type f ! -mtime -1 -print 2>/dev/null)
}

if [[ "${skipped_once_daily}" != "true" ]]; then
  create_daily_backup
  clean_backups
  clean_config_backups
  clean_sessions
  cap_cron_runs
  cap_logs
  clean_generated_dirs
  clean_media_and_queue
  clean_caches
  if [[ "${APPLY}" == "true" && "${ONCE_DAILY}" == "true" ]]; then
    mkdir -p "${state_dir}"
    printf '%s\n' "${today_utc}" > "${once_marker}"
  fi
fi

if [[ "${JSON}" == "true" ]]; then
  jq -cn \
    --argjson ok true \
    --arg root "${ROOT}" \
    --argjson apply "$(if [[ "${APPLY}" == "true" ]]; then echo true; else echo false; fi)" \
    --argjson backupCreated "$(if [[ "${backup_created}" == "true" ]]; then echo true; else echo false; fi)" \
    --argjson backupWouldCreate "$(if [[ "${backup_would_create}" == "true" ]]; then echo true; else echo false; fi)" \
    --argjson skippedOnceDaily "$(if [[ "${skipped_once_daily}" == "true" ]]; then echo true; else echo false; fi)" \
    --argjson deletedPaths "${deleted_paths}" \
    --argjson wouldDeletePaths "${would_delete_paths}" \
    --argjson truncatedFiles "${truncated_files}" \
    --argjson wouldTruncateFiles "${would_truncate_files}" \
    --argjson cappedLogs "${capped_logs}" \
    --argjson wouldCapLogs "${would_cap_logs}" \
    --argjson keepSessionsPerAgent "${KEEP_SESSIONS_PER_AGENT}" \
    --argjson maxCronLines "${MAX_CRON_LINES}" \
    '{
      ok:$ok,
      root:$root,
      apply:$apply,
      backupCreated:$backupCreated,
      backupWouldCreate:$backupWouldCreate,
      skippedOnceDaily:$skippedOnceDaily,
      deletedPaths:$deletedPaths,
      wouldDeletePaths:$wouldDeletePaths,
      truncatedFiles:$truncatedFiles,
      wouldTruncateFiles:$wouldTruncateFiles,
      cappedLogs:$cappedLogs,
      wouldCapLogs:$wouldCapLogs,
      keepSessionsPerAgent:$keepSessionsPerAgent,
      maxCronLines:$maxCronLines
    }'
else
  echo "openclaw-hygiene apply=${APPLY} backup_created=${backup_created} deleted_paths=${deleted_paths} would_delete_paths=${would_delete_paths} truncated_files=${truncated_files} capped_logs=${capped_logs}"
fi
