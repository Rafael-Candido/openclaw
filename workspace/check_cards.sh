#!/bin/bash
set -euo pipefail

cd /var/www/openclaw/workspace

echo "=== Buscando cards no DB Tech (SmartEnvios) ==="
echo

# Buscar cards Aguardando
echo "Cards Aguardando:"
./scripts/notion-helper.sh query adec12e735dc41a3bb7c274b287f3a10 NOTION_SMARTENVIOS_API_KEY "Tech" "Aguardando" | jq -r '.results[] | "ID: \(.id) | Título: \(.properties.Name.title[0].plain_text) | Agente: \(.properties.Agente.select.name // "não definido") | Status: \(.properties.Status.status.name)"' 2>/dev/null || echo "Nenhum card encontrado"

echo
echo "Cards Priorizado:"
./scripts/notion-helper.sh query adec12e735dc41a3bb7c274b287f3a10 NOTION_SMARTENVIOS_API_KEY "Tech" "Priorizado" | jq -r '.results[] | "ID: \(.id) | Título: \(.properties.Name.title[0].plain_text) | Agente: \(.properties.Agente.select.name // "não definido") | Status: \(.properties.Status.status.name)"' 2>/dev/null || echo "Nenhum card encontrado"

echo
echo "Cards Em andamento:"
./scripts/notion-helper.sh query adec12e735dc41a3bb7c274b287f3a10 NOTION_SMARTENVIOS_API_KEY "Tech" "Em andamento" | jq -r '.results[] | "ID: \(.id) | Título: \(.properties.Name.title[0].plain_text) | Agente: \(.properties.Agente.select.name // "não definido") | Status: \(.properties.Status.status.name)"' 2>/dev/null || echo "Nenhum card encontrado"