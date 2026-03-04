# Demandas Geradas - Evolução do Ecossistema (2026-02-27)

## Presidente
1. Criar programa semanal de revisão de SLO dos crons (sucesso, p95, backlog).
2. Exigir checkpoint de progresso por agente quando tarefa > 20 min.
3. Priorizar cards de estabilidade operacional antes de novas features.

## Governança
1. Abrir incidente P0 para `token_mismatch` recorrente no gateway.
2. Implantar regra de contenção: se `token_mismatch` > limiar, bloquear novas execuções forçadas na rodada.
3. Auditar sobreposição de cron e reduzir colisões de agenda.
4. Publicar painel horário de saúde com p95/erro por cron.

## Otimizador
1. Ajustar frequência dinâmica para reduzir `already-running` em horários de pico.
2. Definir budget de execução por rodada e fila de prioridade.
3. Otimizar payloads com respostas determinísticas e curtas (sem raciocínio exposto).

## Engenheiro de Prompt
1. Garantir fatiamento obrigatório para tarefas > 30s por ação.
2. Priorizar retomada de `Em andamento` antes de `Priorizado`.
3. Bloquear ida a `Impedimento` sem contexto mínimo e evidência.

## Mail-Pro / Mail-Person
1. Tratar backlog por lote pequeno determinístico e checkpoint por card.
2. Registrar causa objetiva em falha de entrega (sem texto genérico).
3. Reprocessar pendências antigas com limite por rodada para não travar fila.

## Eng. SmartEnvios
1. Resolver cards travados com plano de micro-entregas e ETA por passo.
2. Usar evidência técnica de repositório antes de escalar.
3. Garantir resposta operacional em português e com resultado objetivo.

## Diretor Tech
1. Normalizar infraestrutura do gateway (service bootstrap + token único).
2. Eliminar dependência frágil de Node via version manager no serviço.
3. Validar healthcheck contínuo com autoteste a cada 10 min.

## Eng. Automação
1. Criar runner de validação contínua (checks + smoke + regressão) com saída JSON.
2. Publicar relatório automático diário de gargalos e ações recomendadas.
3. Orquestrar execução segura de 3 rodadas de recuperação quando SLO cair.
