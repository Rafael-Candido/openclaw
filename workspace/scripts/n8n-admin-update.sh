#!/usr/bin/env bash
set -euo pipefail

# Update n8n workflow metadata using:
# - REST session auth for description (PATCH /rest/workflows/:id)
# - API key auth for tags (PUT /api/v1/workflows/:id/tags)
#
# Includes backup and rollback on failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

read_env_var() {
  local key="$1"
  local file="$2"
  [[ -f "${file}" ]] || return 0
  local line
  line="$(grep -E "^${key}=" "${file}" | head -n 1 || true)"
  [[ -n "${line}" ]] || return 0
  local value="${line#*=}"
  # Trim surrounding quotes only; do not evaluate expansions.
  if [[ "${value}" =~ ^\".*\"$ ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "${value}" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "${value}"
}

N8N_API_BASE_URL="${N8N_API_BASE_URL:-$(read_env_var N8N_API_BASE_URL "${ENV_FILE}")}"
N8N_API_BASE_URL="${N8N_API_BASE_URL:-https://n8n.smartenvios.tec.br/api/v1}"
N8N_WEB_BASE_URL="${N8N_WEB_BASE_URL:-$(read_env_var N8N_WEB_BASE_URL "${ENV_FILE}")}"
N8N_WEB_BASE_URL="${N8N_WEB_BASE_URL:-${N8N_API_BASE_URL%/api/v1}}"
N8N_USERNAME_ADMIN="${N8N_USERNAME_ADMIN:-$(read_env_var N8N_USERNAME_ADMIN "${ENV_FILE}")}"
N8N_PASSWORD_ADMIN="${N8N_PASSWORD_ADMIN:-$(read_env_var N8N_PASSWORD_ADMIN "${ENV_FILE}")}"
N8N_API_KEY="${N8N_API_KEY:-${N8N_ADMIN_API_KEY:-$(read_env_var N8N_ADMIN_API_KEY "${ENV_FILE}")}}"
if [[ -z "${N8N_API_KEY}" ]]; then
  N8N_API_KEY="$(read_env_var N8N_API_KEY "${ENV_FILE}")"
fi
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/n8n-admin-update.sh sync-standard-metadata [--dry-run]

What it does:
  1) Logs in on /rest/login with N8N_USERNAME_ADMIN/N8N_PASSWORD_ADMIN
  2) Updates workflow description via /rest/workflows/:id (PATCH)
  3) Updates workflow tags via /api/v1/workflows/:id/tags (PUT)
  4) Creates backup and auto-rolls back on failure

Env required:
  N8N_USERNAME_ADMIN
  N8N_PASSWORD_ADMIN
  N8N_API_KEY

Optional:
  N8N_API_BASE_URL
  N8N_WEB_BASE_URL
USAGE
}

require_tools() {
  command -v curl >/dev/null 2>&1 || { echo "curl not found"; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo "jq not found"; exit 1; }
}

require_env() {
  [[ -n "${N8N_USERNAME_ADMIN}" ]] || { echo "N8N_USERNAME_ADMIN missing"; exit 1; }
  [[ -n "${N8N_PASSWORD_ADMIN}" ]] || { echo "N8N_PASSWORD_ADMIN missing"; exit 1; }
  [[ -n "${N8N_API_KEY}" ]] || { echo "N8N_API_KEY missing"; exit 1; }
}

COOKIE_JAR="/tmp/n8n_admin_update.cookies"
BROWSER_ID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "browser-id-fallback")"
declare -a BACKUPS=()

login_rest() {
  local payload
  payload="$(jq -n --arg u "${N8N_USERNAME_ADMIN}" --arg p "${N8N_PASSWORD_ADMIN}" '{emailOrLdapLoginId:$u,password:$p}')"
  local code
  code="$(curl -sS -o /tmp/n8n_rest_login.json -w "%{http_code}" \
    -c "${COOKIE_JAR}" \
    -H 'content-type: application/json' \
    -X POST "${N8N_WEB_BASE_URL}/rest/login" \
    --data "${payload}")"
  if [[ "${code}" != "200" ]]; then
    echo "REST login failed (HTTP ${code})"
    cat /tmp/n8n_rest_login.json
    exit 1
  fi
}

rest_get_workflow() {
  local workflow_id="$1"
  curl -sS \
    -b "${COOKIE_JAR}" \
    -H "browser-id: ${BROWSER_ID}" \
    -H 'accept: application/json, text/plain, */*' \
    "${N8N_WEB_BASE_URL}/rest/workflows/${workflow_id}"
}

rest_patch_description() {
  local workflow_id="$1"
  local description="$2"
  local meta_file="/tmp/n8n_rest_meta_${workflow_id}.json"
  rest_get_workflow "${workflow_id}" > "${meta_file}"

  local version_id checksum
  version_id="$(jq -r '.data.versionId // empty' "${meta_file}")"
  checksum="$(jq -r '.data.checksum // empty' "${meta_file}")"
  [[ -n "${version_id}" && -n "${checksum}" ]] || {
    echo "Unable to read version/checksum for ${workflow_id}"
    cat "${meta_file}"
    return 1
  }

  local payload_file="/tmp/n8n_rest_patch_${workflow_id}.json"
  jq -n \
    --arg versionId "${version_id}" \
    --arg description "${description}" \
    --arg expectedChecksum "${checksum}" \
    '{versionId:$versionId,description:$description,expectedChecksum:$expectedChecksum}' \
    > "${payload_file}"

  if (( DRY_RUN == 1 )); then
    echo "[dry-run] PATCH /rest/workflows/${workflow_id}"
    return 0
  fi

  local code
  code="$(curl -sS -o "/tmp/n8n_rest_patch_resp_${workflow_id}.json" -w "%{http_code}" \
    -X PATCH \
    -b "${COOKIE_JAR}" \
    -H "browser-id: ${BROWSER_ID}" \
    -H 'accept: application/json, text/plain, */*' \
    -H 'content-type: application/json' \
    -H "origin: ${N8N_WEB_BASE_URL}" \
    "${N8N_WEB_BASE_URL}/rest/workflows/${workflow_id}" \
    --data @"${payload_file}")"

  [[ "${code}" == "200" ]] || {
    echo "Failed to patch description for ${workflow_id} (HTTP ${code})"
    cat "/tmp/n8n_rest_patch_resp_${workflow_id}.json"
    return 1
  }
}

api_get_all_tags() {
  curl -sS \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_API_BASE_URL}/tags"
}

api_get_workflow_tags() {
  local workflow_id="$1"
  curl -sS \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_API_BASE_URL}/workflows/${workflow_id}/tags"
}

api_put_workflow_tags() {
  local workflow_id="$1"
  local tags_payload_file="$2"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] PUT /api/v1/workflows/${workflow_id}/tags"
    return 0
  fi
  local code
  code="$(curl -sS -o "/tmp/n8n_api_tags_put_${workflow_id}.json" -w "%{http_code}" \
    -X PUT \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -H 'content-type: application/json' \
    "${N8N_API_BASE_URL}/workflows/${workflow_id}/tags" \
    --data @"${tags_payload_file}")"
  [[ "${code}" == "200" ]] || {
    echo "Failed to update tags for ${workflow_id} (HTTP ${code})"
    cat "/tmp/n8n_api_tags_put_${workflow_id}.json"
    return 1
  }
}

backup_workflow_metadata() {
  local workflow_id="$1"
  local backup_file="/tmp/n8n_meta_backup_${workflow_id}.json"
  local rest_json tags_json
  rest_json="$(rest_get_workflow "${workflow_id}")"
  tags_json="$(api_get_workflow_tags "${workflow_id}")"
  jq -n --argjson rest "${rest_json}" --argjson tags "${tags_json}" \
    '{workflowId:$rest.data.id,name:$rest.data.name,description:$rest.data.description,tags:$tags}' \
    > "${backup_file}"
  BACKUPS+=("${backup_file}")
}

rollback_all() {
  if (( ${#BACKUPS[@]} == 0 )); then
    return 0
  fi
  echo "Rolling back metadata changes..."
  for bf in "${BACKUPS[@]}"; do
    local wid desc
    wid="$(jq -r '.workflowId' "${bf}")"
    desc="$(jq -r '.description // ""' "${bf}")"
    jq '[.tags[] | {id:.id}]' "${bf}" > "/tmp/n8n_meta_rollback_tags_${wid}.json"
    rest_patch_description "${wid}" "${desc}" || true
    api_put_workflow_tags "${wid}" "/tmp/n8n_meta_rollback_tags_${wid}.json" || true
  done
}

resolve_tag_ids_payload() {
  local workflow_id="$1"
  shift
  local names=("$@")
  local all_tags_file="/tmp/n8n_all_tags.json"
  api_get_all_tags > "${all_tags_file}"

  local payload_file="/tmp/n8n_tags_payload_${workflow_id}.json"
  jq -n '[]' > "${payload_file}"
  for name in "${names[@]}"; do
    local tid
    tid="$(jq -r --arg n "${name}" '.data[] | select(.name == $n) | .id' "${all_tags_file}" | head -n 1)"
    if [[ -z "${tid}" ]]; then
      echo "Tag '${name}' not found in n8n"
      return 1
    fi
    jq --arg id "${tid}" '. += [{"id":$id}]' "${payload_file}" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "${payload_file}"
  done
  echo "${payload_file}"
}

sync_standard_metadata() {
  # Standard metadata target
  local p_id="gj2LbZNwFi2h9TiR3cJJa"
  local d_id="OVnhZW60VYOXgjdG0tKDw"
  local p_desc="Receives tracking pendency events (webhook + scheduled query), persists tracking-control records, and creates preventive tickets in Zendesk and Central Service."
  local d_desc="Receives delayed-tracking events (webhook + scheduled query), persists tracking-control records, and creates preventive tickets in Zendesk and Central Service."
  local tags=("Zendesk" "Tracking" "CentralService")

  backup_workflow_metadata "${p_id}"
  backup_workflow_metadata "${d_id}"

  local p_tags_payload d_tags_payload
  p_tags_payload="$(resolve_tag_ids_payload "${p_id}" "${tags[@]}")"
  d_tags_payload="$(resolve_tag_ids_payload "${d_id}" "${tags[@]}")"

  rest_patch_description "${p_id}" "${p_desc}"
  rest_patch_description "${d_id}" "${d_desc}"

  api_put_workflow_tags "${p_id}" "${p_tags_payload}"
  api_put_workflow_tags "${d_id}" "${d_tags_payload}"

  echo "Metadata synchronized successfully."
}

main() {
  local cmd="${1:-}"
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      *) echo "Unknown arg: $1"; usage; exit 1 ;;
    esac
    shift
  done

  require_tools
  require_env
  login_rest

  trap 'echo "Error detected. Triggering rollback..."; rollback_all' ERR

  case "${cmd}" in
    sync-standard-metadata)
      sync_standard_metadata
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
