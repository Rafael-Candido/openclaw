#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_FILE="${1:-${PROJECT_ROOT}/workspace/tmp/ecosystem-smoke-$(date +%Y%m%d-%H%M%S).json}"

mkdir -p "$(dirname "${OUT_FILE}")"

run_cmd() {
  local name="$1"
  local timeout_sec="$2"
  shift 2 || true

  local started ended elapsed rc out err
  started="$(date +%s)"
  out="$(mktemp /tmp/ecosmoke-out-XXXXXX.txt)"
  err="$(mktemp /tmp/ecosmoke-err-XXXXXX.txt)"
  rc=0
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_sec}"s "$@" >"${out}" 2>"${err}" || rc=$?
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_sec}"s "$@" >"${out}" 2>"${err}" || rc=$?
  else
    "$@" >"${out}" 2>"${err}" || rc=$?
  fi
  ended="$(date +%s)"
  elapsed=$((ended-started))

  jq -n \
    --arg name "${name}" \
    --argjson rc "${rc}" \
    --argjson elapsed "${elapsed}" \
    --arg stdout "$(cat "${out}" 2>/dev/null | tail -n 20)" \
    --arg stderr "$(cat "${err}" 2>/dev/null | tail -n 20)" \
    '{name:$name,rc:$rc,elapsedSec:$elapsed,stdout:$stdout,stderr:$stderr}'
  rm -f "${out}" "${err}" 2>/dev/null || true
}

checks='[]'
append_check() {
  local item="$1"
  checks="$(jq -cn --argjson a "${checks}" --argjson i "${item}" '$a + [$i]')"
}

append_check "$(run_cmd "syntax_guard" 20 bash -n "${SCRIPT_DIR}/runtime-guard.sh")"
append_check "$(run_cmd "syntax_president" 20 bash -n "${SCRIPT_DIR}/president-mail-demand-cycle.sh")"
append_check "$(run_cmd "syntax_runner" 20 bash -n "${SCRIPT_DIR}/run-cron-20rounds.sh")"
append_check "$(run_cmd "eng_automacao_cycle" 60 "${SCRIPT_DIR}/eng-automacao-deterministic-cycle.sh")"
append_check "$(run_cmd "optimizer_cycle" 60 "${SCRIPT_DIR}/optimizer-deterministic-cycle.sh")"
append_check "$(run_cmd "president_cycle_dry" 60 env PRESIDENT_AUTONOMOUS_MIGRATION_ENABLED=false "${SCRIPT_DIR}/president-mail-demand-cycle.sh")"

ok_count="$(jq '[.[] | select(.rc==0)] | length' <<<"${checks}")"
total_count="$(jq 'length' <<<"${checks}")"
fail_count=$((total_count-ok_count))

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson checks "${checks}" \
  --argjson ok "${ok_count}" \
  --argjson fail "${fail_count}" \
  --argjson total "${total_count}" \
  '{ok:($fail==0),ts:$ts,total:$total,okCount:$ok,failCount:$fail,checks:$checks}' > "${OUT_FILE}"

cat "${OUT_FILE}"
