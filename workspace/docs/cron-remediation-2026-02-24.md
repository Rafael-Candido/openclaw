# Remediacao de Gargalos do Ecossistema (2026-02-24)

## Objetivo
Resolver travamentos percebidos no fluxo Notion + cron + Gmail, executar bateria de validacao e deixar conhecimento documentado para operacao continua.

## Evidencias de Execucao
- Bateria de 20 execucoes de cron em cadeia:
  - `workspace/tmp/cron20-20260224-185730.log`
- Recuperacao dos cards legados do Engenheiro de Prompt:
  - `workspace/tmp/eng-prompt-recovery-20260224-190320.log`

## Diagnostico Inicial
- Inboxes:
  - profissional: 201 nao lidos
  - pessoal: 201 nao lidos
- Cadeia profissional com card em Diretor Tech/Aguardando.
- 11 cards do Engenheiro de Prompt em Aguardando sem captura automatica.

## Resultado da Bateria de 20 Execucoes
Sequencia executada por rodada (4x):
1. Presidente
2. Diretor Tech
3. Mail-Pro
4. Diretor Pessoal
5. Mail-Person

Comportamento observado:
- Rodada 1 drenou o backlog:
  - profissional 201 -> 0 (apos Mail-Pro)
  - pessoal 201 -> 0 (apos Mail-Person)
- Rodadas 2-4 mantiveram estabilidade em 0/0.
- Sem falhas de cron na bateria executada.

## Causas Raiz Confirmadas
1. Estimativa de backlog Gmail inconsistente
- `resultSizeEstimate` com `maxResults=100` retornava valor subestimado em alguns momentos.
- Isso comprometia decisao de criacao/forca da cadeia pelo Presidente.

2. Cards orfaos em Aguardando para Engenheiro de Prompt
- O especialista so capturava Priorizado/Em andamento.
- Cards legados em Aguardando ficavam indefinidamente parados.

## Correcao Aplicada
### 1) Backlog Gmail estabilizado
- Troca para leitura com `maxResults=1` no estimate de nao lidos.
- Arquivos:
  - `workspace/scripts/president-mail-demand-cycle.sh`
  - `workspace/scripts/gmail/process-notion-cards.sh`

### 2) Recuperacao automatica de Aguardando no Engenheiro de Prompt
- Inclusao de `Aguardando` na captura do especialista.
- Prioridade de captura:
  1. Em andamento
  2. Priorizado
  3. Aguardando
- Arquivo:
  - `workspace/scripts/eng-prompt-deterministic-cycle.sh`

### 3) Cadeia sem sobreposicao (mantido)
- Deduplicacao por prefixo real da rotina.
- Criacao permitida quando cadeia vazia e backlog persistente.
- Wake seletivo por dominio (sem acordar todos os crons de uma vez).
- Arquivo:
  - `workspace/scripts/president-mail-demand-cycle.sh`

### 4) Padrao transversal documentado
- Regras de cadeia sem sobreposicao e escalabilidade no pattern.
- Arquivo:
  - `workspace/templates/agent-behavior-patterns.md`

## Estado Final Validado (apos remediacao)
- Inboxes:
  - profissional: 0 nao lidos (apos execucao da cadeia de remediacao)
  - pessoal: 0 nao lidos
- Filas abertas nas cadeias de mail: 0
- Engenheiro de Prompt em Aguardando/Priorizado/Em andamento: 0
- Crons criticos com `status=ok`.

## Observacao Operacional
- Houve erros transitorios de comentario Notion (`HTTP 0`) em tentativas pontuais, sem impedir atualizacao de status/conclusao.
- Recomendacao: manter monitoramento e retry de comentario como melhoria incremental.

## Correcao adicional (SmartEnvios) - 2026-02-24 19:30

Problema observado:
- Engenheiro SmartEnvios ficava em loop no card pai com `action=ready_for_implementation` sem concluir.
- Havia card legado em `Impedimento` fora do fluxo de triagem.

Acoes aplicadas:
1. `workspace/scripts/eng-smartenvios-deterministic-cycle.sh`
- Se card for micro: conclui a micro-fatia com evidência objetiva e libera a próxima.
- Se card pai tiver `MICROPLAN_CHILDREN` e todas as micro-fati as estiverem concluídas: conclui automaticamente o card pai.
- Em falta de contexto (<80 chars): não manda mais para `Impedimento` automático; devolve para `Diretor Tech` em `Priorizado` com pendência objetiva.

2. Cron do SmartEnvios
- Frequência alterada para `every 10m`.
- Payload do cron alinhado para regra nova (sem Impedimento automático por contexto insuficiente).

3. Higienização de legado
- Card `31021016-bd48-8136-ac10-f191d4cac46f` saiu de `Impedimento` e foi devolvido para `Diretor Tech/Priorizado`.

Validacao apos correcao:
- Engenheiro SmartEnvios: `priorizado=0`, `em_andamento=0`, `impedimento=0`.
- Execução forçada de validação retornou `action=parent_completed_from_microplan` e, nas rodadas seguintes, `no_card`.
