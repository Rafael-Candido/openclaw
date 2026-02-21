#!/usr/bin/env bash
set -euo pipefail

NOW_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKUP_ROOT="${PROJECT_ROOT}/backups/sessions"
BACKUP_DIR="${BACKUP_ROOT}/${NOW_UTC}"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}"

SESSION_DIR="${OPENCLAW_CONFIG_DIR}/agents/main/sessions"
RUNTIME_CONFIG="${OPENCLAW_CONFIG_DIR}/openclaw.json"
PROJECT_CONFIG="${PROJECT_ROOT}/openclaw.json"

mkdir -p "${BACKUP_DIR}"

echo "Creating backup at: ${BACKUP_DIR}"

rsync -a "${SESSION_DIR}/" "${BACKUP_DIR}/sessions/"
cp -f "${RUNTIME_CONFIG}" "${BACKUP_DIR}/openclaw.runtime.json"
cp -f "${PROJECT_CONFIG}" "${BACKUP_DIR}/openclaw.project.json"

cat > "${BACKUP_DIR}/MANIFEST.txt" <<EOF
created_at_utc=${NOW_UTC}
source_sessions=${SESSION_DIR}
source_runtime_config=${RUNTIME_CONFIG}
source_project_config=${PROJECT_CONFIG}
EOF

echo "Backup complete: ${BACKUP_DIR}"
