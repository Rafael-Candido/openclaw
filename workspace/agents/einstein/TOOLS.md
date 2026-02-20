# TOOLS.md - Einstein

## SmartEnvios MCP — ÚNICA FORMA DE ACESSAR APIs

**Script:** `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh`

NÃO usar `mcporter`, `mcp`, ou qualquer outro comando. O ÚNICO caminho é o script acima.

### Comandos disponíveis:

```bash
# Login (faz automaticamente se token não existir)
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh login

# Listar TODAS as ferramentas disponíveis no MCP
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh tools

# Chamar qualquer ferramenta por nome
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call <nome_ferramenta> '<json_args>'
```

### Exemplos:

```bash
# Consultar CEP
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call cep_lookup '{"cep":"14025710"}'

# Cotação de frete
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call smartenvios_quote_freight '{"zip_code_start":"14025710","zip_code_end":"01001010","volumes":[{"quantity":1,"length":20,"height":20,"weight":0.2,"width":20}]}'
```

### Fluxo obrigatório quando pedirem algo operacional:

1. **Primeiro:** rodar `./smartenvios-mcp.sh tools` para ver se a ferramenta existe no MCP
2. **Se existir:** executar via `./smartenvios-mcp.sh call <ferramenta> '<args>'`
3. **Se NÃO existir:** criar card no Notion para o Diretor Tech (ver seção abaixo)

### Exemplo real — Jira:

Se pedirem "crie atividade no Jira":
1. Usar o helper local:
   - `/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh create ...`
2. Passar assignee por nome (`--assignee "Rodrigo"`), nunca exigir `accountId` antes.
3. Passar `--reason` para o helper inferir tipo (`Bug`/`Story`/`Task`).
4. Confirmar no retorno JSON:
   - `classification.product`
   - `classification.projectLabel`
   - `classification.integration`
   - `classification.category`
   - `issue.status` (esperado `To Do` / `Tarefas pendentes`)

## Notion SmartEnvios (escalonamento)

Usar quando Einstein **não conseguir resolver** algo via MCP.

**Database ID:** `adec12e735dc41a3bb7c274b287f3a10`
**API Key:** usar via skill `notion` ou variável `$NOTION_SMARTENVIOS_API_KEY`

### Criar card de escalonamento:

```bash
source /var/www/openclaw/.env
curl -sS -X POST "https://api.notion.com/v1/pages" \
  -H "Authorization: Bearer ${NOTION_SMARTENVIOS_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "parent": {"database_id": "adec12e735dc41a3bb7c274b287f3a10"},
    "properties": {
      "Name": {"title": [{"text": {"content": "TÍTULO DA DEMANDA"}}]},
      "Status": {"status": {"name": "Aguardando"}},
      "Tipo": {"select": {"name": "OpenClaw"}},
      "Agente": {"select": {"name": "Tech"}}
    }
  }'
```

### Propriedades obrigatórias:
- **Status:** `Aguardando`
- **Tipo:** `OpenClaw`
- **Solicitante:** `Rafael Pereira`
- **Agente:** `Tech`

## Discord API

Acesso direto às mensagens de canais Discord via API do bot.

**Token:** `$DISCORD_BOT_TOKEN` (no `.env`)

```bash
source /var/www/openclaw/.env
# Últimas 100 mensagens de um canal
curl -sS "https://discord.com/api/v10/channels/<CHANNEL_ID>/messages?limit=100" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}"
```

## Jira SmartEnvios

Acesso operacional via helper:

- Script: `/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh`
- Cache assignees: `/var/www/openclaw/workspace/agents/einstein/.pi/jira-assignees.json`
- Cache fields: `/var/www/openclaw/workspace/agents/einstein/.pi/jira-field-cache.json`

**Credenciais no `.env`:**
- `JIRA_BASE_URL=https://smartenv.atlassian.net/`
- `JIRA_EMAIL=rafael.pereira@smartenvios.com`
- `JIRA_API_TOKEN`
- `JIRA_PROJECT_KEY=SME`

```bash
# Resolver assignee e guardar cache
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh assignee-resolve "Rodrigo"

# Criar tarefa com classificação automática de dropdowns + tipo
/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh create \
  --summary "DHL tracking não atualizando - envio teste 6302554694" \
  --description "Tracking não está atualizando corretamente no portal." \
  --assignee "Rodrigo" \
  --reason "bug" \
  --integration "DHL" \
  --category "Tracking" \
  --product "APP" \
  --project-label "SME project" \
  --priority "Highest" \
  --link "https://portal.smartenvios.com/rastreamento/codigo-de-rastreio/6302554694" \
  --link "https://mydhl.express.dhl/br/pt/tracking.html#/results?id=6302554694"
```

## Gmail Scripts (referência)

```bash
/var/www/openclaw/workspace/scripts/gmail/gmail.sh pro labels
/var/www/openclaw/workspace/scripts/gmail/gmail.sh pro list "is:unread"
```
