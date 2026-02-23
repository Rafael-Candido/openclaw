# Exemplos de Uso: Jira e Grafana via MCP SmartEnvios

## 📋 Visão Geral

O MCP SmartEnvios oferece acesso a múltiplas ferramentas via API, incluindo Jira e Grafana. Este documento fornece exemplos práticos de uso operacional.

## 🔧 Configuração Inicial

### 1. Login no MCP
```bash
# Login com credenciais SmartEnvios
./scripts/smartenvios-mcp.sh login

# Resposta esperada:
# {"jsonrpc":"2.0","id":1,"result":{"session_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."}}
```

### 2. Listar Ferramentas Disponíveis
```bash
# Verificar todas as ferramentas (40+)
./scripts/smartenvios-mcp.sh tools
```

## 🎯 Jira (direto via MCP)

### Verificar ferramentas Jira disponíveis
```bash
./scripts/smartenvios-mcp.sh tools | jq -r '.result.tools[].name' | rg '^jira_'
```

### Criar issue no Jira
```bash
./scripts/smartenvios-mcp.sh call jira_create_issue '{
  "summary": "Adicionar permissionamento nas rotas de API do ms_atendimento",
  "description": "Implementar controle de permissões e validar contagem de tickets.",
  "issue_type": "Story",
  "project_key": "SME",
  "fields": {
    "priority": {"name": "Highest"}
  }
}'
```

### Atribuir e mover para To Do
```bash
./scripts/smartenvios-mcp.sh call jira_search_users '{"query":"Guilherme Dantas","maxResults":10}'
./scripts/smartenvios-mcp.sh call jira_assign_issue '{"issue_key":"SME-12345","account_id":"<accountId>"}'
./scripts/smartenvios-mcp.sh call jira_transition_issue '{"issue_key":"SME-12345","transition_name":"To Do"}'
```

## 📊 Grafana (produção)

### Consulta rápida de erro por serviço/rota
```bash
./scripts/smartenvios-mcp.sh call grafana_loki_query_range '{
  "query": "{app=\"ms.atendimento\"} |= \"permission\"",
  "limit": 200,
  "direction": "backward"
}'
```

## 🧩 Fluxo recomendado: bug -> logs -> card técnico

1. Identificar repositório/serviço da rota.
2. Validar erro no Grafana (Loki) com query por rota, erro e app.
3. Criar card no Notion profissional para Diretor Tech:
```bash
./scripts/smartenvios-mcp.sh call notion_request '{"path":"pages","method":"POST","body":{
  "parent":{"database_id":"adec12e735dc41a3bb7c274b287f3a10"},
  "properties":{
    "Name":{"title":[{"text":{"content":"[Bug] Falha na rota X - diagnóstico com logs"}}]},
    "Status":{"select":{"name":"Aguardando"}},
    "Tipo":{"select":{"name":"OpenClaw"}},
    "Agente":{"select":{"name":"Diretor Tech"}}
  },
  "children":[
    {"object":"block","type":"heading_2","heading_2":{"rich_text":[{"type":"text","text":{"content":"Contexto"}}]}},
    {"object":"block","type":"paragraph","paragraph":{"rich_text":[{"type":"text","text":{"content":"Resumo do bug e impacto."}}]}},
    {"object":"block","type":"heading_2","heading_2":{"rich_text":[{"type":"text","text":{"content":"Evidências (Grafana)"}}]}},
    {"object":"block","type":"paragraph","paragraph":{"rich_text":[{"type":"text","text":{"content":"Serviço, rota, erro, timestamps e correlação."}}]}},
    {"object":"block","type":"heading_2","heading_2":{"rich_text":[{"type":"text","text":{"content":"Plano de correção"}}]}},
    {"object":"block","type":"paragraph","paragraph":{"rich_text":[{"type":"text","text":{"content":"Ação técnica recomendada e validação."}}]}},
    {"object":"block","type":"paragraph","paragraph":{"rich_text":[{"type":"text","text":{"content":"Direcionar para Engenheiro SmartEnvios."}}]}}
  ]
}}'
```

## 🎫 Zendesk (Suporte)

### Buscar Ticket por ID
```bash
# Consultar ticket específico
./scripts/smartenvios-mcp.sh call zendesk_get_ticket '{"ticket_id":201732}'

# Resposta inclui:
# - Status, prioridade, assunto
# - Comentários e histórico
# - Informações do solicitante
```

### Buscar Tickets por Query
```bash
# Buscar tickets com filtros
./scripts/smartenvios-mcp.sh call zendesk_search_tickets '{"query":"status:open priority:high"}'

# Buscar por código de rastreamento
./scripts/smartenvios-mcp.sh call zendesk_search_tickets '{"tracking_code":"BR123456789BR"}'
```

### Criar Novo Ticket
```bash
# Criar ticket de suporte
./scripts/smartenvios-mcp.sh call zendesk_create_ticket '{
  "ticket": {
    "subject": "Problema com cálculo de frete",
    "comment": {
      "body": "O cálculo de frete está retornando valores incorretos para CEP 14020-510.\n\nDetalhes:\n- Produto: Livro (2kg)\n- CEP origem: 01310-100\n- CEP destino: 14020-510\n- Valor esperado: R$ 25,90\n- Valor retornado: R$ 45,20"
    },
    "priority": "high",
    "tags": ["frete", "bug", "calculadora"]
  }
}'
```

### Adicionar Comentário a Ticket
```bash
# Adicionar comentário interno
./scripts/smartenvios-mcp.sh call zendesk_add_comment '{
  "ticket_id": 201732,
  "body": "Ticket escalado para equipe de desenvolvimento. Bug confirmado no microserviço ms.connectors.",
  "public": false
}'
```

## 📈 Pipedrive (CRM)

### Listar Leads
```bash
# Listar leads ativos
./scripts/smartenvios-mcp.sh call pipedrive_list_leads '{"status":"open","limit":10}'

# Filtrar por owner
./scripts/smartenvios-mcp.sh call pipedrive_list_leads '{"owner_id":123,"archived_status":"not_archived"}'
```

### Criar Novo Lead
```bash
# Criar lead no Pipedrive
./scripts/smartenvios-mcp.sh call pipedrive_create_lead '{
  "lead": {
    "title": "Empresa XYZ - Integração API",
    "person_id": 456,
    "organization_id": 789,
    "label_ids": ["lead", "api-integration"],
    "value": {"amount": 5000, "currency": "BRL"},
    "expected_close_date": "2026-03-15"
  }
}'
```

### Converter Lead em Negócio
```bash
# Converter lead em deal
./scripts/smartenvios-mcp.sh call pipedrive_convert_lead '{
  "lead_id": "abc123-def456",
  "payload": {
    "pipeline_id": 1,
    "stage_id": 2,
    "title": "Contrato Empresa XYZ",
    "value": 5000,
    "currency": "BRL"
  }
}'
```

## 🗄️ Bancos de Dados

### Consulta PostgreSQL
```bash
# Consultar única linha
./scripts/smartenvios-mcp.sh call pg_fetch_one '{
  "query": "SELECT * FROM orders WHERE status = $1 LIMIT 1",
  "params": ["pending"]
}'
```

### Consulta MongoDB
```bash
# Buscar documento único
./scripts/smartenvios-mcp.sh call mongo_fetch_one '{
  "collection": "tickets",
  "filter": {"status": "open", "priority": "high"}
}'
```

## 🔄 Fluxos de Trabalho Completos

### 1. Reportar Bug e Criar Ticket
```bash
# 1. Login
./scripts/smartenvios-mcp.sh login

# 2. Criar ticket Zendesk
./scripts/smartenvios-mcp.sh call zendesk_create_ticket '{
  "ticket": {
    "subject": "Bug reportado via MCP",
    "comment": {"body": "Descrição do bug..."},
    "priority": "normal"
  }
}'

# 3. Criar issue no Notion (Jira)
./scripts/smartenvios-mcp.sh call notion_request '{"path":"pages", "method": "POST", "body": {...}}'

# 4. Registrar em banco de dados
./scripts/smartenvios-mcp.sh call pg_fetch_one '{
  "query": "INSERT INTO bug_reports (ticket_id, description, created_at) VALUES ($1, $2, NOW()) RETURNING id",
  "params": ["201732", "Bug reportado"]
}'
```

### 2. Consultar Métricas e Dashboard
```bash
# 1. Listar dashboards disponíveis
./scripts/smartenvios-mcp.sh call metabase_list_dashboards

# 2. Consultar dashboard de logística
./scripts/smartenvios-mcp.sh call metabase_get_dashboard '{"dashboard_id":77}'

# 3. Executar query de card específico
./scripts/smartenvios-mcp.sh call metabase_query_card '{"card_id":1442}'

# 4. Registrar consulta em log
./scripts/smartenvios-mcp.sh call mongo_fetch_one '{
  "collection": "dashboard_queries",
  "filter": {"dashboard_id": 77, "user": "einstein"}
}'
```

## ⚠️ Tratamento de Erros

### Erro Comum: Autenticação
```bash
# Se falhar, verificar session_token
echo "Session token necessário para todas as chamadas após login"
```

### Erro Comum: Permissões
```bash
# Algumas ferramentas podem requerer permissões específicas
echo "Verificar se o usuário tem acesso à ferramenta solicitada"
```

### Fallback para Interface Web
```bash
# Se MCP falhar, sugerir interface web
echo "Como alternativa, acesse:"
echo "- Jira: https://smartenvios.atlassian.net"
echo "- Grafana: https://grafana.smartenvios.com"
echo "- Zendesk: https://smartenvios.zendesk.com"
```

## 📚 Boas Práticas

### 1. Cache de Session Token
```bash
# Armazenar token para reuso
SESSION_TOKEN=$(./scripts/smartenvios-mcp.sh login | jq -r '.result.session_token')
export SESSION_TOKEN
```

### 2. Validação de Parâmetros
```bash
# Sempre validar parâmetros antes de chamar
if [[ -z "$CEP" ]] || [[ ! "$CEP" =~ ^[0-9]{8}$ ]]; then
  echo "CEP inválido. Formato: 8 dígitos."
  exit 1
fi
```

### 3. Logging e Monitoramento
```bash
# Registrar todas as chamadas MCP
log_mcp_call() {
  local tool=$1
  local params=$2
  echo "$(date): $tool - $params" >> /var/log/mcp-calls.log
}
```

### 4. Rate Limiting
```bash
# Respeitar limites de API
sleep 1  # Aguardar 1 segundo entre chamadas
```

## 🔧 Scripts de Exemplo

### monitor-jira-issues.sh
```bash
#!/bin/bash
# Monitorar issues Jira abertas via MCP Jira

ISSUES=$(./scripts/smartenvios-mcp.sh call jira_search_issues '{
  "jql": "project = SME AND statusCategory != Done ORDER BY updated DESC",
  "maxResults": 20
}')

echo "Issues abertas no Jira:"
echo "$ISSUES" | jq -r '.issues[]? | "• \(.key) - \(.fields.summary) - \(.fields.priority.name // "N/A")"'
```

### dashboard-metrics.sh
```bash
#!/bin/bash
# Extrair métricas do dashboard Grafana/Metabase

DASHBOARD_ID=76
CARD_ID=1441

METRICS=$(./scripts/smartenvios-mcp.sh call metabase_query_card "{\"card_id\":$CARD_ID}")

echo "Métricas do dashboard $DASHBOARD_ID:"
echo "$METRICS" | jq -r '.data.rows[] | join(", ")'
```

---

**Nota:** As ferramentas Jira e Grafana são acessadas via MCP direto. Sempre verifique a disponibilidade com `./scripts/smartenvios-mcp.sh tools` antes de usar.
