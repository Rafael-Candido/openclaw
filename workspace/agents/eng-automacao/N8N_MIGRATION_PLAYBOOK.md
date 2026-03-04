# N8N Migration Playbook - Engenheiro de Automacao

## Objetivo

Migrar workflows do n8n legado para o novo n8n, distribuindo por contexto:
- `sales`
- `product`
- `finance`

## Estado padrao atual

- O cliente de API usa contexto: `workspace/scripts/n8n-api.sh --context <ctx> ...`
- O MCP client n8n tambem usa contexto: `workspace/scripts/n8n-mcp.sh --context <ctx> ...`
- O ciclo do Engenheiro de Automacao classifica card n8n por contexto e valida `can-write` antes de alterar workflow.
- O script de migracao em lote existe: `workspace/scripts/n8n-migrate-contexts.sh`.

## Variaveis obrigatorias no `.env`

- `OLD_N8N_URL`
- `OLD_N8N_API_KEY`
- `N8N_API_BASE_URL`
- `N8N_SALES_API_KEY`
- `N8N_PRODUCT_API_KEY`
- `N8N_FINANCE_API_KEY`
- `N8N_ADMIN_API_KEY`

## Comandos operacionais

### 1. Validar acesso por contexto

```bash
workspace/scripts/n8n-api.sh --context product can-write <workflow_id>
workspace/scripts/n8n-api.sh --context sales can-write <workflow_id>
workspace/scripts/n8n-api.sh --context finance can-write <workflow_id>
```

### 2. Migracao em lote (obrigatorio iniciar com dry-run)

```bash
workspace/scripts/n8n-migrate-contexts.sh --dry-run --limit 250
workspace/scripts/n8n-migrate-contexts.sh --apply --limit 250
```

Observacoes:
- Limite da API antiga: `limit <= 250`.
- O script evita duplicacao por nome no destino.
- Classificacao automatica:
  - termos de financeiro -> `finance`
  - termos de sales/comercial/crm/lead/pipedrive -> `sales`
  - restante -> `product`

### 3. Validacao pos-migracao

```bash
workspace/scripts/n8n-migrate-contexts.sh --dry-run --limit 250
```

Resultado esperado: itens em `SKIP ... already_exists`.

## Processo para mudanca segura em workflow

1. `get` do workflow atual.
2. Salvar backup local.
3. Aplicar alteracao minima no JSON.
4. `put` no contexto correto.
5. Validar conexoes e execucao.
6. Documentar evidencia no card Notion.

## Erros comuns e regra de resposta

- Erro de contexto (`can-write=false`):
  - nao forcar alteracao;
  - comentar no card o contexto esperado.
- Erro de auth:
  - validar variaveis `.env`;
  - nunca hardcode de token.
- Erro de classificacao (ex.: person x lead):
  - corrigir mapeamento semantico no fluxo;
  - registrar regra no card e neste playbook se recorrente.

## Criterio de pronto

- Workflow criado/atualizado no contexto correto.
- `can-write=true` no contexto do dono.
- Fluxo executando sem quebra de conexoes.
- Evidencia no card (comando + resultado + impacto).
