#!/usr/bin/env bash
# Configuração do sistema de batch adaptativo para Mail-Pro/Mail-Person
#
# Metas de throughput (referência): 200 emails em ~10s (list + get em triage + batch modify paralelo).
# Ajuste MAIL_BATCH_MAX_LIMIT e GMAIL_BATCH_PARALLEL conforme rede/API.

# Configurações de batch adaptativo
export MAIL_BATCH_MIN_LIMIT="${MAIL_BATCH_MIN_LIMIT:-25}"        # Mínimo de emails por batch
export MAIL_BATCH_MAX_LIMIT="${MAIL_BATCH_MAX_LIMIT:-200}"       # Máximo para drenagem agressiva
export MAIL_BATCH_STEP_UP="${MAIL_BATCH_STEP_UP:-25}"
export MAIL_BATCH_STEP_DOWN="${MAIL_BATCH_STEP_DOWN:-10}"
export MAIL_BATCH_SUCCESS_STREAK="${MAIL_BATCH_SUCCESS_STREAK:-1}"
export MAIL_BATCH_SLOW_RUN_SEC="${MAIL_BATCH_SLOW_RUN_SEC:-45}"  # Detecta lentidão cedo e ajusta rápido

# Paralelismo no Gmail (batch-mark-read, batch-archive): mais = menos tempo total, mais carga na API
export GMAIL_BATCH_PARALLEL="${GMAIL_BATCH_PARALLEL:-24}"

# Configurações de throughput emergencial (quando backlog > limite)
export MAIL_BACKLOG_EMERGENCY_THRESHOLD="${MAIL_BACKLOG_EMERGENCY_THRESHOLD:-40}"
export MAIL_EMERGENCY_BATCH_LIMIT="${MAIL_EMERGENCY_BATCH_LIMIT:-200}"  # Drenagem máxima em backlog alto
export MAIL_EMERGENCY_FREQUENCY_MIN="${MAIL_EMERGENCY_FREQUENCY_MIN:-10}"

# Configurações de logging
export MAIL_BATCH_LOGGING="${MAIL_BATCH_LOGGING:-true}"

# Para usar: source /var/www/openclaw/workspace/scripts/gmail/batch-config.sh
# ou adicione ao .env do projeto
