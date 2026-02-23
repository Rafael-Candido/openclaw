#!/usr/bin/env bash
# Configuração de exemplo para notion-helper.sh
# Copie para notion-helper-config.sh e ajuste conforme necessário

# Número máximo de tentativas para requests que falham com rate limit (429) ou erros 5xx
export NOTION_MAX_RETRIES=3

# Delay base em segundos para backoff exponencial (2^attempt * base_delay + jitter)
export NOTION_BASE_DELAY=2

# Habilitar logging detalhado das tentativas (true/false)
export NOTION_ENABLE_LOGGING=true

# Jitter máximo em segundos (aleatoriedade adicionada ao delay para evitar thundering herd)
export NOTION_MAX_JITTER=3

# Timeout para requests curl em segundos
export NOTION_CURL_TIMEOUT=30

# Para usar: source /var/www/openclaw/workspace/scripts/notion-helper-config.sh
# ou adicione ao .env do projeto