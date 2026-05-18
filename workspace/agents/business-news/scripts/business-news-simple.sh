#!/usr/bin/env bash
# Compatibilidade: o cron canonico usa o script central do workspace.

set -euo pipefail

exec /var/www/openclaw/workspace/scripts/business-news-simple.sh "$@"
