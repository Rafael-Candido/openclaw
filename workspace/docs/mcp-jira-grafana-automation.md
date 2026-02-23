# MCP Jira/Grafana - Auditoria e Automacao

## Objetivo

Garantir operacao MCP-first para Jira e Grafana, com deteccao automatica de falhas e escalonamento tecnico no Notion profissional sem depender de supervisao manual.

## Contrato operacional

- Einstein deve usar MCP sempre para transacionais Jira/Grafana.
- Falha persistente no MCP nao deve gerar workaround local.
- Falha persistente deve gerar card tecnico no Notion profissional para Diretor Tech.
- Correcao estrutural deve ser implementada no repositório `/var/www/mcp`.

## Auditoria automatica implantada

Script: `workspace/scripts/mcp-governance-audit.sh`

Checks executados por rodada:

1. Login MCP (`smartenvios-mcp.sh login`)
2. Lista de tools (`tools/list`)
3. Presenca de tools criticas:
   - Jira: `jira_create_issue`, `jira_search_users`, `jira_assign_issue`, `jira_get_issue`, `jira_get_myself`
   - Grafana: `grafana_request`, `grafana_loki_query_range`, `grafana_loki_labels`
4. Smoke Jira:
   - `jira_get_myself`
   - `jira_search_users`
5. Smoke Grafana:
   - `grafana_request` em `api/health`
   - `grafana_loki_labels`

Saida padrao:

- `MCP_AUDIT_STATUS`
- `MCP_AUDIT_REPORT`
- `MCP_AUDIT_FAIL_COUNT`
- `MCP_AUDIT_CARD_ID` (quando houver escalonamento)

## Integracao com Governanca

`workspace/scripts/governance-check.sh` executa a auditoria MCP em toda rodada:

- Etapa: `run_mcp_governance_audit`
- Timeout dedicado: `GOV_MCP_AUDIT_TIMEOUT_SEC` (default 90s)
- Em falha:
  - registra bottleneck de severidade alta
  - cria/atualiza card no Notion profissional para Diretor Tech
  - anexa evidencias no card automaticamente

## Aprendizados desta rodada

1. Jira MCP operacional para transacionais e classificacao por campos.
2. Gargalo recorrente observado em Grafana MCP tende a ser autenticacao/permissao (ex.: HTTP 403).
3. A correção correta para gargalo MCP é em `/var/www/mcp`, e nao fallback local em agente.
4. Sem auditoria continua, erros MCP viram falhas silenciosas no fluxo de agentes.

## Proximo nivel (recomendado)

1. Adicionar check de escrita Jira em ambiente de homologacao (issue de teste com cleanup).
2. Adicionar healthcheck dedicado no MCP para Grafana com diagnostico de credencial.
3. Publicar resumo sintetico no painel da Governanca quando `MCP_AUDIT_STATUS != ok`.
