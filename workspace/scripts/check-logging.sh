#!/usr/bin/env bash
set -euo pipefail

# Minimal enforcement for logging policy.
# - Fails if console.log appears in production paths.
# - Excludes common non-production dirs.

ROOT="${1:-.}"
EXCLUDES=(
  "--exclude-dir=.git"
  "--exclude-dir=node_modules"
  "--exclude-dir=dist"
  "--exclude-dir=build"
  "--exclude-dir=scripts"
  "--exclude=*.md"
)

if grep -RIn "console\.log\s*(" "$ROOT" "${EXCLUDES[@]}"; then
  echo "❌ Logging policy violation: console.log found in production paths."
  exit 1
fi

echo "✅ Logging check passed: no console.log found in production paths."
