# Jira Classification Rules

Use this file as the default policy when creating Jira issues from Discord requests.

## 1) Assignee resolution and cache

- Always resolve assignee by name first.
- Do not ask for `accountId` before attempting resolution.
- Cache file:
  - `workspace/agents/einstein/.pi/jira-assignees.json`

Commands:

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh assignee-resolve "Rodrigo"
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh assignee-list
```

## 2) Issue type by motive

- `Bug`: bug, erro, falha, incidente, nao funciona, nao atualiza.
- `Story`: melhoria, evolucao, feature, otimizacao, aprimoramento.
- `Task`: tarefa, ajuste, solicitacao, atividade operacional.

## 3) Dropdowns by demand identity

Fill these fields when available in Jira custom fields:

- Product (`Produto`)
- Project label (`Projeto`)
- Integration (`Integracao`)
- Category (`Categoria`)

Inference defaults:

- Product:
  - `APP` for app/aplicativo.
  - `APP` for tracking/rastreamento contexts.
  - `Portal` for portal/site.
  - `API` for api/webhook.
- Project label:
  - `SME project` by default.
- Integration:
  - DHL, Correios, Jadlog, Loggi, Azul Cargo, Melhor Envio (by keyword).
- Category:
  - Tracking for tracking/rastreio/rastreamento.
  - Integracao for integration/webhook.
  - Operacao for envio/fluxo operacional.
  - Acesso for login/senha.
  - Financeiro for cobranca/fatura.

## 4) Priority and status

- Priority must default to `Highest`.
- After create, move issue to `To Do` / `Tarefas pendentes` when transition exists.

## 5) Canonical create command

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh create \
  --summary "TITULO" \
  --description "DESCRICAO" \
  --assignee "NOME" \
  --reason "bug|melhoria|tarefa" \
  --product "APP|Portal|API" \
  --project-label "SME project" \
  --integration "DHL|Correios|..." \
  --category "Tracking|Operacao|..." \
  --priority "Highest"
```
