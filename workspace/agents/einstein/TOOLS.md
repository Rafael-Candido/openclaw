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

# Listar somente nomes de ferramentas (1 por linha)
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh tools-names

# Validar se existe ferramenta por regex (retorna true/false)
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh has-tool '^jira_'

# Chamar qualquer ferramenta por nome
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call <nome_ferramenta> '<json_args>'
```

### Regra crítica de execução (evitar approval-pending)

- Para MCP via `exec`, usar **comando direto** com caminho absoluto.
- Não usar `cd`, `source`, `&&`, `;` ou `|` nas chamadas MCP.
- Preferir sempre:
  - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh tools-names`
  - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh has-tool '^jira_'`
  - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call <tool> '<args>'`

### Exemplos:

```bash
# Consultar CEP
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call cep_lookup '{"cep":"14025710"}'

# Cotação de frete
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call smartenvios_quote_freight '{"zip_code_start":"14025710","zip_code_end":"01001010","volumes":[{"quantity":1,"length":20,"height":20,"weight":0.2,"width":20}]}'
```

### Fluxo obrigatório quando pedirem algo operacional:

1. **Primeiro:** rodar `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh tools-names` (ou `has-tool`) para ver se a ferramenta existe no MCP
2. **Se existir:** executar via `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call <ferramenta> '<args>'`
3. **Se NÃO existir:** escalar no Notion para o Diretor Tech (ver seção abaixo)
4. **Para criação de demanda (card/atividade/chamado/tarefa):** usar Jira via MCP **somente com pedido explícito de criação**.
5. Se `jira_*` falhar no MCP, escalar correção no Notion profissional para Diretor Tech (MCP-only; sem fallback local).

### Gatilho obrigatório para criar Jira

- Só criar Jira quando houver comando explícito (ex.: `crie`, `abra`, `gere`, `registre` atividade/tarefa/chamado/card/ticket).
- Se a mensagem for dúvida, contexto, atualização, diagnóstico ou pedido de verificação, **não criar Jira**.
- Se ficar ambíguo, fazer 1 pergunta de confirmação e aguardar: `Você quer que eu crie uma atividade no Jira para isso?`.

### Validação antes de declarar indisponibilidade

- `Approval required`, `approval-pending` ou `updates will arrive after completion` significam que a execução ainda não terminou.
- Isso não autoriza responder `MCP indisponível` e não equivale a erro 503.
- Nessa situação, aguarde o resultado final ou informe bloqueio operacional/execução pendente.
- Não declarar `MCP indisponível` só porque uma tentativa falhou.
- Repetir uma checagem objetiva com o mesmo script:
  - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh tools-names`
  - para Jira: `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_get_myself '{}'`
- Se `tools` falhar, mas `jira_get_myself` ou a tool final responder, tratar como degradação parcial e seguir.
- Só usar mensagem de indisponibilidade quando a checagem objetiva também falhar.

### Notificações automáticas `[JIRA]`

- Se a entrada for e-mail/notificação automática de Jira (assunto iniciando com `[JIRA]`) sem pedido explícito do usuário, não responder.
- Tratar como informativo e seguir com `HEARTBEAT_OK`.

### Exemplo real — Jira (via MCP)

Se pedirem explicitamente "crie atividade no Jira" (ou "crie/abra card/atividade/chamado/tarefa" no contexto SmartEnvios):
1. Validar se o MCP expõe Jira:
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh has-tool '^jira_'`
2. Resolver assignee por nome:
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_search_users '{"query":"Rodrigo Silvestre","maxResults":10}'`
3. Classificar com aprendizado antes do create:
   - `/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh classify --summary "..." --description "..." --reason "..." --assignee "..."`
4. Criar issue via MCP usando os campos retornados pela classificação:
   - descrição obrigatória com template:
     - `## Solicitação do usuário:`
     - `{{mensagem original}}`
     - `## Objetivo`
     - `{{escopo melhorado}}`
     - `## Critérios de aceite`
     - `{{resultado esperado}}`
   - regra de qualidade da descrição:
     - `Objetivo` deve traduzir a solicitação em escopo executável (não copiar texto literal).
     - incluir bullets com ações concretas e, quando houver, separar `Backend` e `Frontend`.
     - `Critérios de aceite` devem validar cada regra de negócio relevante (incluindo cenários condicionais como elegibilidade/saldo/bloqueio), com evidência e sem regressão.
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_create_issue '{"summary":"...","description":"...","issue_type":"Task","product":"<classificacao.product>","project_label":"<classificacao.projectLabel>","integration":"<classificacao.integration>","category":"<classificacao.category>","component":"<classificacao.component>"}'`
   - **não usar `customfield_*` no `jira_create_issue`** (o create do MCP deve receber campos semânticos).
5. Definir prioridade alvo:
   - se o usuário pediu prioridade explícita, usar essa prioridade;
   - senão, fallback `Highest`.
5.1 Se o usuário pedir criação em lote ("uma tarefa para cada tópico"):
   - criar 1 issue por tópico, mantendo a ordem original;
   - aplicar prioridade decrescente por ordem: `Highest`, `High`, `Medium`, `Low`, `Lowest`;
   - se houver mais de 5 tópicos, manter `Lowest` para os tópicos extras.
6. Forçar prioridade após create (workaround runtime atual):
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_update_issue '{"issue_key":"SME-123","fields":{"priority":{"name":"<PRIORIDADE_ALVO>"}}}'`
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_get_issue '{"issue_key":"SME-123"}'` (validar prioridade)
7. Validar classificação pós-create:
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_get_issue '{"issue_key":"SME-123"}'`
   - se `Produto/Projeto` vierem vazios, aplicar `jira_update_issue` com os campos corretos e validar novamente.
   - se `Categoria` vier vazia, preencher pelo campo `labels` (ex.: `categoria:cotacao`) e validar novamente.
8. Registrar aprendizado:
   - `/var/www/openclaw/workspace/agents/einstein/scripts/jira-helper.sh learn-from-issue --issue-key "SME-123" --context "<summary + descrição + links>"`
9. Atribuir:
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_assign_issue '{"issue_key":"SME-123","account_id":"<accountId>"}'`
10. Garantir `To Do` / pendente:
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_list_transitions '{"issue_key":"SME-123"}'`
   - `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call jira_transition_issue '{"issue_key":"SME-123","transition_name":"To Do"}'`
11. Confirmar no retorno:
   - `key`, `status`, `assignee`, `priority`.
12. Se falhar:
   - retentar 1x no MCP;
   - abrir/atualizar card técnico no Notion profissional para Diretor Tech corrigir o MCP em `/var/www/mcp`;
   - não criar workaround local fora do MCP.
13. Preencher campos de classificação quando disponíveis no projeto:
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
- não incluir corpo da issue na resposta (proibido colar `## Solicitação do usuário`, `## Objetivo`, `## Critérios de aceite`).
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

## KPI Primeiro Envio (canal comercial)

Use o coletor deterministico abaixo para perguntas como:
- `quantos primeiros envios tivemos nessa semana?`
- `qual o valor total de oportunidade na semana?`

Comando (padrao: semana domingo-sabado no timezone `America/Sao_Paulo`):

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/primeiro-envio-kpi.sh --output json
```

Com intervalo explicito:

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/primeiro-envio-kpi.sh \
  --start-date 2026-03-08 \
  --end-date 2026-03-14 \
  --output json
```

Saida principal:
- `first_shipments_count`
- `total_opportunity_value_brl`
- `period.label_ptbr`

Regra:
- nao responder com "historico incompleto" sem antes executar esse script;
- se `partial=true`, informar leitura parcial e retentar com `--max-pages` maior.

## Aprendizado Discord por Sessões (Q&A + Perfil)

Para enriquecer o Einstein com o servidor inteiro em lotes incrementais:

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/discord-learning-session.sh --output text
```

Para sessões maiores:

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/discord-learning-session.sh \
  --max-channels 10 \
  --max-pages-per-channel 20 \
  --limit 50 \
  --output json
```

Para varredura contínua em várias sessões (até esgotar pendências ou atingir limite):

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/discord-learning-runner.sh \
  --max-sessions 12 \
  --sleep-seconds 3 \
  --max-channels 8 \
  --max-pages-per-channel 8 \
  --limit 50
```

Artefatos:
- Estado/cursor por canal: `workspace/agents/einstein/.pi/discord-learning-state.json`
- Base pergunta→resposta: `workspace/agents/einstein/.pi/discord-learning-qa.jsonl`
- Perfil de respostas do Einstein: `workspace/agents/einstein/.pi/discord-learning-profile.json`
- Relatórios por sessão: `workspace/agents/einstein/.pi/discord-learning-sessions/`

## Política Jira

- Einstein cria/atualiza/atribui/transiciona issues via **MCP-only** para Jira.
- Helper local `jira-helper.sh` é permitido apenas para classificação com aprendizado (`classify`) e feedback pós-criação (`learn-from-issue`).
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
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call grafana_loki_query_range '{"query":"{app=\"ms.atendimento\"} |= \"<rota ou erro>\"","limit":200}'
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

## Interface com Especialista de Suporte de Software

Quando o pedido do Discord for de atendimento operacional de software (central/plataforma/CRM), fazer handoff para o especialista:

```bash
/var/www/openclaw/workspace/agents/einstein/scripts/handoff-suporte-software.sh "<titulo>" "<descricao>" "Alta" "<nome do solicitante>"
```

Regra:
- usar esse handoff quando não for só dúvida rápida e exigir investigação operacional;
- manter Einstein como interface no Discord e usar o card para execução do especialista;
- após criar o handoff, responder ao usuário com o ID/URL do card gerado.
