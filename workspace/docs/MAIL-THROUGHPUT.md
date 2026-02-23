# Throughput de e-mail e metas de execução

## Metas

- **200 e-mails em ~10s:** list + get (triage) + análise em memória + batch mark-read/archive em paralelo.
- **Card concluído em até 30s:** script determinístico (Notion query, update, comment) em < 5s; turno do agente (LLM) com timeout 30s para cards simples; cards complexos continuam com timeout maior.

## Otimizações aplicadas

1. **Workflow sem N× get/thread:** `workflow.sh` chama `triage.sh` uma vez (1 list + N get) e depois `analyze-from-triage.sh` em memória sobre o JSON do triage. Antes: 1 list + N get (triage) + N get + N thread (analyze.sh) = 2N get + N thread a menos.
2. **Batch mark-read e archive:** `gmail.sh` ações `batch-mark-read` e `batch-archive` com paralelismo configurável (`GMAIL_BATCH_PARALLEL`, default 8). `process-workflow.sh` aplica labels/drafts por mensagem e no final chama batch-mark-read e batch-archive com todos os ids.
3. **List com LIMIT:** `triage.sh` usa o LIMIT do caller como `maxResults` do Gmail list (até 500). Chamar `workflow.sh pro 200` para processar até 200 mensagens.
4. **Batch config:** `MAIL_BATCH_MAX_LIMIT` 50 (subir para 200 quando estável), `MAIL_BATCH_SLOW_RUN_SEC` 120s, `GMAIL_BATCH_PARALLEL` 8.

## Como medir

- Executar `workspace/scripts/analyze-cron-logs.sh 20` para ver duração média/máx e erros por cron.
- Para e-mail: cronometrar `process-workflow.sh pro 200` (ou `workflow.sh pro 200` + `process-workflow`) com backlog real; ajustar `GMAIL_BATCH_PARALLEL` e limite conforme rede.

## Card em 30s

O tempo total de um card é: script determinístico (segundos) + turno do agente (até timeout do cron). Para “concluído em 30s”:

- Scripts `eng-prompt-deterministic-cycle.sh` e `eng-smartenvios-deterministic-cycle.sh` já são rápidos (só Notion API).
- O cron hoje usa `timeoutSeconds` 240/300. Reduzir para 30 no payload faria o agente ser interrompido em 30s; útil só se houver caminho “quick-win” (ex.: card concluído com comentário mínimo) ou se os cards forem triviais. Caso contrário, manter timeout maior e usar a métrica “card concluído em até 30s” como alvo de desenho (evitar tarefas que exijam mais que 30s quando possível).
