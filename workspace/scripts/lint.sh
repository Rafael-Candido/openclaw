#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/private/var/www/openclaw"
VENV_DIR="${ROOT_DIR}/workspace/.venv-lint"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

"${VENV_DIR}/bin/pip" install --quiet --upgrade pip shellcheck-py ruff

echo "[lint] shellcheck"
mapfile -t sh_files < <(rg --files -g '*.sh' "${ROOT_DIR}/workspace/scripts")
"${VENV_DIR}/bin/shellcheck" "${sh_files[@]}"

echo "[lint] ruff"
"${VENV_DIR}/bin/ruff" check "${ROOT_DIR}/workspace/scripts/notion_export_recursive.py"

echo "[lint] ok"
