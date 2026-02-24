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
3. **Se NÃO existir:** escalar no Notion para o Diretor Tech (ver seção abaixo)
4. **Para criação de demanda (card/atividade/chamado/tarefa):** usar Jira por padrão via MCP.
5. Se `jira_*` falhar no MCP, escalar correção no Notion profissional para Diretor Tech (MCP-only; sem fallback local).

### Exemplo real — Jira (via MCP)

Se pedirem "crie atividade no Jira" (ou "crie card/atividade/chamado/tarefa" no contexto SmartEnvios):
1. Validar se o MCP expõe Jira:
   - `./smartenvios-mcp.sh tools | jq -r '.result.tools[].name' | rg '^jira_'`
2. Resolver assignee por nome:
   - `./smartenvios-mcp.sh call jira_search_users '{"query":"Rodrigo Silvestre","maxResults":10}'`
3. Criar issue:
   - `./smartenvios-mcp.sh call jira_create_issue '{"summary":"...","description":"...","issue_type":"Task","product":"Integração Plataformas","project_label":"Connector Magento 2","category":"Integração","component":"ms.connectors"}'`
4. Definir prioridade alvo:
   - se o usuário pediu prioridade explícita, usar essa prioridade;
   - senão, fallback `Highest`.
5. Forçar prioridade após create (workaround runtime atual):
   - `./smartenvios-mcp.sh call jira_update_issue '{"issue_key":"SME-123","fields":{"priority":{"name":"<PRIORIDADE_ALVO>"}}}'`
   - `./smartenvios-mcp.sh call jira_get_issue '{"issue_key":"SME-123"}'` (validar prioridade)
6. Validar classificação pós-create:
   - `./smartenvios-mcp.sh call jira_get_issue '{"issue_key":"SME-123"}'`
   - se `Produto/Projeto/Categoria` vierem vazios, aplicar `jira_update_issue` com os campos corretos e validar novamente.
7. Atribuir:
   - `./smartenvios-mcp.sh call jira_assign_issue '{"issue_key":"SME-123","account_id":"<accountId>"}'`
8. Garantir `To Do` / pendente:
   - `./smartenvios-mcp.sh call jira_list_transitions '{"issue_key":"SME-123"}'`
   - `./smartenvios-mcp.sh call jira_transition_issue '{"issue_key":"SME-123","transition_name":"To Do"}'`
9. Confirmar no retorno:
   - `key`, `status`, `assignee`, `priority`.
10. Se falhar:
   - retentar 1x no MCP;
   - abrir/atualizar card técnico no Notion profissional para Diretor Tech corrigir o MCP em `/var/www/mcp`;
   - não criar workaround local fora do MCP.
11. Preencher campos de classificação quando disponíveis no projeto:
   - `Produto`
   - `Projeto`
   - `Categoria`
   - `Componente`

### Resposta padrão para criação Jira (Discord/WhatsApp)

Usar formato curto e único:

```text
<menção do solicitante> Atividade criada no Jira.
Key: SME-12345
Responsável: Nome
Tipo/Prioridade: <TIPO> / <PRIORIDADE>
Link: https://smartenv.atlassian.net/browse/SME-12345
```

Regra:
- manter o texto no mesmo idioma do pedido do usuário.
- enviar somente esse bloco (não concatenar respostas).
- para pedido em português, não incluir nenhuma frase em inglês.
- quando houver solicitante identificável, a menção na primeira linha é obrigatória.

## Notion SmartEnvios (somente escalonamento)

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

## Política Jira

- Einstein é **MCP-only** para Jira.
- Melhorias/falhas do fluxo Jira devem ser tratadas no repositório `/var/www/mcp`.
- Quando houver falha persistente no MCP, escalar no Notion profissional para `Diretor Tech` com evidências técnicas.

## Bug Triage com Grafana (produção) + Notion Tech

Quando reportarem bug com rota/endpoints:

1. Mapear app/serviço da rota:
```bash
rg -n "rota|endpoint|controller|path" /var/www/ms.* -S
```
2. Buscar erro em produção no Grafana via MCP:
```bash
./smartenvios-mcp.sh call grafana_loki_query_range '{"query":"{app=\"ms.atendimento\"} |= \"<rota ou erro>\"","limit":200}'
```
3. Consolidar diagnóstico técnico com evidências de log (erro + serviço + janela temporal).
4. Criar card no Notion profissional para `Diretor Tech`:
- DB: `adec12e735dc41a3bb7c274b287f3a10`
- `Status=Aguardando`, `Tipo=OpenClaw`, `Agente=Diretor Tech`
- Corpo obrigatório:
  - Contexto do bug
  - Evidências (logs/rotas)
  - Causa provável
  - Plano de correção
  - "Direcionar para Engenheiro SmartEnvios"

## Gmail Scripts (referência)

```bash
/var/www/openclaw/workspace/scripts/gmail/gmail.sh pro labels
/var/www/openclaw/workspace/scripts/gmail/gmail.sh pro list "is:unread"
```
