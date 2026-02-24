# Auditoria de Padronização — 2026-02-23

## Objetivo

Garantir que regras transversais não fiquem presas em scripts/cron específicos, evitando que novos agentes/crons nasçam sem padrão operacional.

## Escopo auditado

- `cron/jobs.json`
- `workspace/scripts/*deterministic-cycle.sh`
- `workspace/templates/agent-behavior-patterns.md`
- `workspace/patterns/cron-lifecycle.md`
- `workspace/patterns/cron-implementation-guide.md`

## Regras promovidas para Patterns (transversal)

1. Ordem de captura do especialista:
- retomar primeiro `Em andamento`, depois captar `Priorizado` (mais antigo primeiro).

2. Orçamento determinístico:
- padrão de 1 card por rodada por agente (salvo exceção explícita do cron).

3. Execução longa:
- comentário de progresso com ETA revisado quando passar janela operacional sem atualização.

4. Stale check confiável:
- usar última atividade assinada do agente em comentários como fonte principal;
- usar `last_edited_time` da página apenas como fallback.

5. Contexto insuficiente:
- se card não tiver contexto mínimo para execução, comentar bloqueio e mover para `Impedimento`.

6. Verificação pós-write:
- após `update-status`, validar estado final no Notion antes de prosseguir.

7. Triagem de diretor (transação curta):
- lock em `Em andamento` -> roteamento/assinatura -> retorno para `Priorizado`.

## Arquivos de patterns atualizados

- `workspace/templates/agent-behavior-patterns.md`
- `workspace/patterns/cron-lifecycle.md`
- `workspace/patterns/cron-implementation-guide.md`

## Scripts alinhados ao padrão nesta rodada

1. Especialistas:
- `workspace/scripts/eng-prompt-deterministic-cycle.sh`
  - prioridade de retomada em `Em andamento`;
  - progresso com ETA;
  - stale check por comentários do agente;
  - fallback de contexto insuficiente para `Impedimento`.
- `workspace/scripts/eng-smartenvios-deterministic-cycle.sh`
  - mesmas regras acima para evitar divergência entre especialistas.

2. Diretores:
- `workspace/scripts/director-tech-deterministic-cycle.sh`
- `workspace/scripts/director-personal-deterministic-cycle.sh`
- `workspace/scripts/director-business-deterministic-cycle.sh`
  - seleção ajustada para retomar `Em andamento` antes de novos `Aguardando/Priorizado`.

## Itens que permanecem específicos (não devem virar padrão global)

1. Regras de roteamento por domínio:
- ex.: título com "mail/email" -> `Mail-Pro`;
- ex.: título com "prompt/governan/pattern" -> `Engenheiro de Prompt`.

Motivo:
- dependem de contexto de negócio e banco Notion (pessoal/profissional/negócios).

2. Regras de fallback por stack externa:
- Jira/MCP/Grafana, mapeamento de campos customizados.

Motivo:
- são políticas de integração por domínio (Einstein/SmartEnvios), não lifecycle universal.

3. Políticas de heartbeat de canal:
- contrato binário `HEARTBEAT_OK/ALERTA` para `main/presidente`.

Motivo:
- política de comunicação específica de canal/agent role.

## Critério de aceitação desta auditoria

- Patterns centrais refletem regras transversais críticas já implementadas em produção.
- Scripts principais (diretores + especialistas técnicos) aderem ao padrão atualizado.
- Regras específicas de domínio permanecem fora do padrão global para evitar sobre-generalização.

