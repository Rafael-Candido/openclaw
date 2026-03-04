# TOOLS.md - Engenheiro de Automação (SmartEnvios)

## n8n API (operacional por contexto)

- Script base: `workspace/scripts/n8n-api.sh`
- Operações:
  - `get`: leitura de workflow
  - `put`: publicação de workflow
  - `can-write`: validação de permissão de escrita
- Contextos:
  - `sales`
  - `product`
  - `finance`
  - `admin`
  - `old` (legado, somente leitura/migração)

Exemplos:

```bash
workspace/scripts/n8n-api.sh --context product get gj2LbZNwFi2h9TiR3cJJa
workspace/scripts/n8n-api.sh --context product put gj2LbZNwFi2h9TiR3cJJa /tmp/payload.json
workspace/scripts/n8n-api.sh --context product can-write gj2LbZNwFi2h9TiR3cJJa
workspace/scripts/n8n-api.sh --context old get gj2LbZNwFi2h9TiR3cJJa
```

## n8n Admin Metadata

- Script: `workspace/scripts/n8n-admin-update.sh`
- Uso atual:
  - sincronização de descrição e tags padrão

```bash
workspace/scripts/n8n-admin-update.sh sync-standard-metadata
workspace/scripts/n8n-admin-update.sh sync-standard-metadata --dry-run
```

## Workflows principais (atual)

- Pendency flow: `gj2LbZNwFi2h9TiR3cJJa`
- Delayed flow: `OVnhZW60VYOXgjdG0tKDw`
- Shared subflow: `sd0NsiodNnqKTZW6`

## Migração OLD -> NEW

- Script: `workspace/scripts/n8n-migrate-contexts.sh`
- Pré-requisitos no `.env`:
  - `OLD_N8N_URL`
  - `OLD_N8N_API_KEY`
  - `N8N_API_BASE_URL`
  - `N8N_SALES_API_KEY`
  - `N8N_PRODUCT_API_KEY`
  - `N8N_FINANCE_API_KEY`

Comandos:

```bash
workspace/scripts/n8n-migrate-contexts.sh --dry-run --limit 250
workspace/scripts/n8n-migrate-contexts.sh --apply --limit 250
```

## Checklist técnico rápido

1. `get` do workflow atual.
2. editar JSON local (/tmp).
3. publicar com payload mínimo (`name,nodes,connections,settings.executionOrder`).
4. validar conexões (`broken=0`).
5. validar execuções recentes (`status=success`).
6. documentar no card Notion.

## Regra de segurança

- Nunca commitar credencial.
- Nunca publicar mudança grande em uma rodada.
- Sempre manter caminho de rollback com JSON anterior salvo.
