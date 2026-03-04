#!/usr/bin/env bash
set -euo pipefail

# Keep session continuity without unbounded growth.
# Policy:
# - retain recent session files (N days)
# - cap file count per agent sessions dir

OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${HOME}/.openclaw}"
ROOT="${OPENCLAW_CONFIG_DIR}/agents"
KEEP_DAYS="${SESSION_KEEP_DAYS:-7}"
MAX_FILES_PER_AGENT="${SESSION_MAX_FILES_PER_AGENT:-400}"

[[ "${KEEP_DAYS}" =~ ^[0-9]+$ ]] || KEEP_DAYS=7
[[ "${MAX_FILES_PER_AGENT}" =~ ^[0-9]+$ ]] || MAX_FILES_PER_AGENT=400

processed=0
deleted_age=0
deleted_cap=0

tmp_list="$(mktemp /tmp/openclaw-session-dirs-XXXXXX)"
find "${ROOT}" -type d -name sessions 2>/dev/null > "${tmp_list}" || true
while IFS= read -r sdir; do
  [[ -d "${sdir}" ]] || continue
  processed=$((processed + 1))

  # 1) Remove old run files by age.
  while IFS= read -r f; do
    rm -f "${f}" 2>/dev/null || true
    deleted_age=$((deleted_age + 1))
  done < <(find "${sdir}" -type f -name '*.jsonl' -mtime "+${KEEP_DAYS}" 2>/dev/null)

  # 2) Cap file count to avoid unlimited growth.
  count="$(find "${sdir}" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${count}" =~ ^[0-9]+$ ]] && (( count > MAX_FILES_PER_AGENT )); then
    remove_n=$((count - MAX_FILES_PER_AGENT))
    while IFS= read -r f; do
      rm -f "${f}" 2>/dev/null || true
      deleted_cap=$((deleted_cap + 1))
    done < <(find "${sdir}" -type f -name '*.jsonl' -print0 2>/dev/null | xargs -0 ls -1tr 2>/dev/null | head -n "${remove_n}")
  fi

  # 3) Light cleanup of transient locks.
  find "${sdir}" -type f \( -name '*.lock' -o -name '*.bak*' \) -mtime +2 -delete 2>/dev/null || true
done < "${tmp_list}"
rm -f "${tmp_list}" 2>/dev/null || true

jq -cn \
  --argjson ok true \
  --arg root "${ROOT}" \
  --argjson keepDays "${KEEP_DAYS}" \
  --argjson maxFilesPerAgent "${MAX_FILES_PER_AGENT}" \
  --argjson processed "${processed}" \
  --argjson deletedByAge "${deleted_age}" \
  --argjson deletedByCap "${deleted_cap}" \
  '{
    ok:$ok,
    root:$root,
    keepDays:$keepDays,
    maxFilesPerAgent:$maxFilesPerAgent,
    processedDirs:$processed,
    deletedByAge:$deletedByAge,
    deletedByCap:$deletedByCap
  }'
