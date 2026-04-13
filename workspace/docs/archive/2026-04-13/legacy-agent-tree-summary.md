# Resumo da arvore legada de agentes

Data: 2026-04-13

## Decisao

A camada `workspace/agents/repo-*` e o antigo `workspace/agents/backend-engineer` deixam de ser arvore operacional ativa.

Motivo:
- o contrato atual centraliza engenharia SmartEnvios em `eng-smartenvios`;
- repositorios especificos sao contexto tecnico da demanda, nao agentes independentes;
- manter um agente por repositorio gerava deriva de contratos, bootstrap e ownership.

## Substituicao operacional

- Backend/API/MCP/infra SmartEnvios: `Engenheiro SmartEnvios`
- Automacoes n8n: `Engenheiro de Automacao`
- Suporte operacional de software: `Especialista de Suporte de Software`
- Estrutura OpenClaw, prompts, docs e crons: `Engenheiro de Prompt`
- Negocios Canper: `Especialista de Negocios`

## Regras de migracao

- Demandas que citam `/var/www/ms.*`, `/var/www/lgc.core`, `/var/www/mcp` ou outro repo SmartEnvios devem registrar o repo no corpo do card.
- O campo `Agente` deve apontar para o especialista canonico, nao para `repo-*`.
- Se surgir um dominio que nao cabe nos especialistas existentes, aplicar primeiro `workspace/docs/OPENCLAW-OPERATING-CONTRACT.json#agentExpansionProtocol`.
