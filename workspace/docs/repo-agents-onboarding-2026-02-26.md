# Repo Agents Onboarding

Date: 2026-02-26

## Objetivo

Criar um especialista por repositório em `/var/www` para absorver regra de negócio, arquitetura e operação, permitindo delegação direta entre agentes e pelo Presidente.

## O que foi criado

- Script gerador idempotente:
  - `workspace/scripts/bootstrap-repo-agents.sh`
- Índice central de roteamento:
  - `workspace/agents/repo-index.json`
- Agentes por repositório:
  - `workspace/agents/repo-*/AGENTS.md`
  - `workspace/agents/repo-*/IDENTITY.md`
  - `workspace/agents/repo-*/BOOTSTRAP.md`

## Regras de operação

1. Roteamento obrigatório via `workspace/agents/repo-index.json`.
2. Demandas técnicas com repo explícito devem ir para o agente desse repo.
3. Demanda cross-repo deve ser fatiada em subtarefas por repo.
4. Se repo não estiver no índice, fallback para `Engenheiro SmartEnvios` e ação de atualização do índice.

## Presidente com insights de execução

O ciclo do Presidente agora inclui `executionInsights` com base em logs de:
- `cron/runs/*.jsonl`
- `cron/jobs.json`

Campo novo no JSON de saída do Presidente:
- `executionInsights.topIssues`: jobs com mais sinais de erro/timeouts.
- `executionInsights.staleJobs`: jobs habilitados sem execução recente.

## Comando de manutenção

Regenerar agentes e índice (idempotente):

```bash
workspace/scripts/bootstrap-repo-agents.sh /var/www
```

