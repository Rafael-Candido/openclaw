# Jira Classification Rules

Use this file as the default policy when creating Jira issues from Discord requests.

## 1) Assignee resolution and cache

- Always resolve assignee by name first.
- Do not ask for `accountId` before attempting resolution.
- Cache file: `workspace/agents/einstein/.pi/jira-assignees.json`

Commands:

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh assignee-resolve "Rodrigo"
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh assignee-list
```

## 2) Issue type by motive

- `Bug`: bug, erro, falha, incidente, nao funciona, nao atualiza.
- `Story`: melhoria, evolucao, feature, otimizacao, aprimoramento.
- `Task`: tarefa, ajuste, solicitacao, atividade operacional.

## 3) Classificacao de Produto/Projeto/Categoria

Fill these fields when available in Jira custom fields:

- Product (`Produto`)
- Project label (`Projeto`)
- Integration (`Integracao`)
- Category (`Categoria`)
- Component (`Componente`)

Inference defaults:

- Product:
  - `Integração Plataformas` for integration/connector/platform contexts.
  - `Tracking` for tracking/rastreamento contexts.
  - `Dashboard` for dashboard contexts.
  - `Não se aplica` as fallback.
- Project label:
  - connector-specific label when detected (`Magento`, `VTEX`, `Shopify`, etc).
  - `Não se aplica` as fallback.
- Integration:
  - DHL, Correios, Jadlog, Loggi, Azul Cargo, Melhor Envio (by keyword).
- Category:
  - Tracking for tracking/rastreio/rastreamento.
  - Integracao for integration/webhook.
  - Cotacao for quote/frete.
  - Etiqueta for label.
  - Operacao for envio/fluxo operacional.
  - Acesso for login/senha.
  - Financeiro for cobranca/fatura.
- Component:
  - `ms.connectors` for integration/connector.
  - `ms.tracking` for tracking.
  - `Não se aplica` as fallback.

## 4) Aprendizado automatico (online)

`jira-helper.sh` now learns continuously from created issues:

- Learning cache: `workspace/agents/einstein/.pi/jira-classification-learning.json`
- Learning events log: `workspace/agents/einstein/.pi/jira-classification-events.jsonl`
- During `create`, helper:
  - predicts fields using learned token→value history;
  - creates the issue;
  - reads final values from Jira and feeds the learning cache.

Operational commands:

```bash
# Inspect learning quality (top values/tokens per field)
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh learning-report

# Force learning from an existing issue (including manually corrected issues)
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh learn-from-issue --issue-key "SME-12345"
```

## 5) Priority and status

- Priority must default to `Highest`.
- For multi-topic requests ("uma tarefa para cada tópico"), create one issue per topic in order and assign descending priorities:
  - 1st `Highest`, 2nd `High`, 3rd `Medium`, 4th `Low`, 5th `Lowest`, extra topics `Lowest`.
- After create, move issue to `To Do` / `Tarefas pendentes` when transition exists.

## 5.1) Description quality gate

- Keep structure:
  - `## Solicitação do usuário:`
  - `## Objetivo`
  - `## Critérios de aceite`
- `Objetivo` must be an executable scope, not a copy of the user message.
- If request has split ownership, explicitly separate scope by area:
  - `Backend: ...`
  - `Frontend: ...`
- `Critérios de aceite` must validate business rules cited in request (including conditional rules), with concrete scenarios + evidence + no regression.

## 6) Auto notifications (no response)

- If input is an automatic Jira email/notification (subject starts with `[JIRA]`) and there is no explicit user request, do not reply.
- Treat it as informational heartbeat only.

## 7) Canonical flow

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh classify \
  --summary "TITULO" \
  --description "DESCRICAO" \
  --assignee "NOME" \
  --reason "bug|melhoria|tarefa"

/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh create \
  --summary "TITULO" \
  --description "## Solicitação do usuário:\n<MENSAGEM>\n\n## Objetivo\n<ESCOPO MELHORADO>\n\n## Critérios de aceite\n- <CRITÉRIO 1>\n- <CRITÉRIO 2>" \
  --assignee "NOME" \
  --reason "bug|melhoria|tarefa" \
  --product "Integração Plataformas|Tracking|..." \
  --project-label "Connector Magento 2|..." \
  --integration "DHL|Correios|..." \
  --category "Tracking|Operacao|..." \
  --component "ms.connectors|ms.tracking|..." \
  --priority "Highest"
```

## 8) MCP create payload guard

- When calling `jira_create_issue` via MCP, always send semantic fields:
  - `product`, `project_label`, `integration`, `category`, `component`
- Never send `customfield_*` directly in MCP create payload.
- After create, read the issue and force correction with `jira_update_issue` when:
  - `Produto` is empty
  - `Projeto` is empty
  - `Categoria` is empty (use `labels`, e.g. `categoria:cotacao`)
