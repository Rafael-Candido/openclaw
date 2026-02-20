#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <backup_dir>"
  echo "Example: $0 /private/var/www/openclaw/backups/sessions/20260220T060000Z"
  exit 1
fi

BACKUP_DIR="$1"
SESSION_BACKUP_DIR="${BACKUP_DIR}/sessions"
RUNTIME_CONFIG_BACKUP="${BACKUP_DIR}/openclaw.runtime.json"
PROJECT_CONFIG_BACKUP="${BACKUP_DIR}/openclaw.project.json"

SESSION_DIR="/Users/rafaelcanper/.openclaw/agents/main/sessions"
RUNTIME_CONFIG="/Users/rafaelcanper/.openclaw/openclaw.json"
PROJECT_CONFIG="/private/var/www/openclaw/openclaw.json"

if [[ ! -d "${SESSION_BACKUP_DIR}" ]]; then
  echo "Backup sessions directory not found: ${SESSION_BACKUP_DIR}"
  exit 1
fi

if [[ ! -f "${RUNTIME_CONFIG_BACKUP}" || ! -f "${PROJECT_CONFIG_BACKUP}" ]]; then
  echo "Backup config files not found in: ${BACKUP_DIR}"
  exit 1
fi

echo "Stopping gateway..."
openclaw gateway stop || true

echo "Restoring session files..."
mkdir -p "${SESSION_DIR}"
rsync -a --delete "${SESSION_BACKUP_DIR}/" "${SESSION_DIR}/"

echo "Restoring configs..."
cp -f "${RUNTIME_CONFIG_BACKUP}" "${RUNTIME_CONFIG}"
cp -f "${PROJECT_CONFIG_BACKUP}" "${PROJECT_CONFIG}"

echo "Starting gateway..."
openclaw gateway start
sleep 2
openclaw health >/dev/null

echo "Rollback complete from backup: ${BACKUP_DIR}"
