# TOOLS.md - Especialista de Suporte de Software

## Fontes principais

- Notion profissional: `NOTION_SMARTENVIOS_API_KEY` + DB `adec12e735dc41a3bb7c274b287f3a10`
- Jira: via MCP SmartEnvios (`jira_*`)
- Central/Plataforma/CRM: via script local com Basic Auth
- Repositórios locais: `/var/www/*`

## Script de acesso a backoffice (Basic Auth)

Use:

```bash
/var/www/openclaw/workspace/agents/esp-suporte-software/scripts/support-backoffice-api.sh <service> <METHOD> <path>
```

Services aceitos:
- `plataform`
- `central`
- `crm`

Exemplos:

```bash
/var/www/openclaw/workspace/agents/esp-suporte-software/scripts/support-backoffice-api.sh plataform GET /
/var/www/openclaw/workspace/agents/esp-suporte-software/scripts/support-backoffice-api.sh central GET /health
/var/www/openclaw/workspace/agents/esp-suporte-software/scripts/support-backoffice-api.sh crm GET /health
```

## Jira via MCP

```bash
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh tools-names
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_search_issues '{"jql":"project = SME ORDER BY created DESC","maxResults":5}'
```

## Notion helper

```bash
/var/www/openclaw/workspace/scripts/notion-helper.sh query adec12e735dc41a3bb7c274b287f3a10 NOTION_SMARTENVIOS_API_KEY "Especialista de Suporte de Software" Priorizado Em andamento
```

## GitHub / código local

- Preferir repositórios locais em `/var/www/`.
- `git_hub_token` pode ser usado para operações remotas quando necessário.
