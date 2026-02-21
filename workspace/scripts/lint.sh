#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENV_DIR="${ROOT_DIR}/workspace/.venv-lint"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

"${VENV_DIR}/bin/pip" install --quiet --upgrade pip shellcheck-py ruff

echo "[lint] shellcheck"
# shellcheck disable=SC2046
"${VENV_DIR}/bin/shellcheck" $(rg --files -g '*.sh' "${ROOT_DIR}/workspace/scripts")

echo "[lint] ruff"
"${VENV_DIR}/bin/ruff" check "${ROOT_DIR}/workspace/scripts/notion_export_recursive.py"

echo "[lint] ok"
