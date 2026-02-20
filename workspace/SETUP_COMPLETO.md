# Setup Completo do Ambiente OpenClaw

**Documento único de referência** consolidando todo o setup, arquitetura, fluxos operacionais e implementações do ambiente OpenClaw.

**Última atualização:** 2026-02-20

---

## 1. Visão Geral

O OpenClaw é um sistema de agentes autônomos que opera através de:
- **Gateway OpenClaw:** gerencia agentes, crons, canais (Discord, WhatsApp, WebChat)
- **Notion:** sistema de cards para fluxo operacional (Aguardando → Priorizado → Em andamento → Concluído)
- **Agentes especializados:** Main (Presidente), Diretores (3), Especialistas (Mail-Pro, Mail-Person), Einstein, Governança, Otimização

**Estrutura base:**
- Workspace: `/var/www/openclaw/workspace`
- Config: `/var/www/openclaw/openclaw.json`
- Env: `/var/www/openclaw/.env`
- Logs: `/var/www/openclaw/logs/gateway.log`

---

## 2. Estrutura do Workspace

```
/var/www/openclaw/
├── workspace/
│   ├── agents/
│   │   ├── einstein/          # Agente Einstein (SmartEnvios Support)
│   │   └── backend-engineer/  # Engenheiro Backend
│   ├── scripts/
│   │   ├── gmail/             # Scripts Gmail (triagem, workflow)
│   │   └── smartenvios-mcp.sh # Cliente MCP SmartEnvios
│   ├── docs/
│   │   └── development/
│   │       └── LOGGING_AND_RULES.md
│   ├── templates/
│   │   └── notion-card-openclaw.md
│   ├── memory/                # Notas diárias
│   ├── FLUXO_AGENTES.md       # Fluxo operacional Notion
│   ├── AGENTS.md              # Regras e padrões dos agentes
│   ├── PLANO_PROJETO.md       # Plano de projeto (logging)
│   ├── TOOLS.md               # Ferramentas e skills disponíveis
│   ├── NOTION.md              # Workspaces Notion configurados
│   ├── KNOWLEDGE.md           # Conhecimento histórico
│   └── SETUP_COMPLETO.md      # Este documento
├── openclaw.json              # Configuração do gateway
├── .env                       # Variáveis de ambiente (credenciais)
└── logs/
    └── gateway.log            # Logs do gateway
```

---

## 3. Configuração do Gateway (openclaw.json)

### 3.1. Agentes Configurados

**Main (Presidente):**
- ID: `main`
- Workspace: `/var/www/openclaw/workspace`
- Modelo: `openai/gpt-5.1-codex` (primary), fallbacks: Claude Sonnet 4.5, Gemini 1.5 Pro, Claude 3 Haiku

**Einstein (SmartEnvios Support):**
- ID: `einstein`
- Workspace: `/var/www/openclaw/workspace/agents/einstein`
- Modelo: `anthropic/claude-sonnet-4-5` (primary)
- **Gatilho Discord:** menção `@1439351480514646087` ou palavra "einstein"
- **Restrições:** sem `exec`, `gateway`, `sessions_*`, `subagents`, `cron`
- **Tools permitidas:** `read`, `web_search`, `web_fetch`, `message`
- **Sandbox:** `workspaceAccess: "ro"` (read-only)

### 3.2. Canais Configurados

**Discord:**
- `groupPolicy: "open"`
- Menções `@1439351480514646087` → roteadas para agente `einstein`
- Todas as mensagens Discord → `einstein` (100% Discord)

**WhatsApp:**
- `dmPolicy: "allowlist"`
- `allowFrom: ["+5516992793422"]`
- DM → agente `main` (respondidas apenas para o utilizador)

**WebChat:**
- Canal principal → agente `main`

### 3.3. Skills Configuradas

- `notion` → Notion SmartEnvios (`NOTION_SMARTENVIOS_API_KEY`)
- `notion-personal` → Notion Pessoal (`NOTION_PERSONAL_API_KEY`)
- `notion-canper` → Notion Canper (`NOTION_CANPER_API_KEY`)
- `nano-banana-pro` → Gemini AI (`GEMINI_API_KEY`)
- `sag` → SAG API (`SAG_API_KEY`)

### 3.4. Logging

- Level: `debug`
- File: `/var/www/openclaw/logs/gateway.log`
- Console: `debug` (pretty style)

---

## 4. Variáveis de Ambiente (.env)

### 4.1. OpenClaw Gateway

```bash
OPENCLAW_GATEWAY_TOKEN=97fb8d9c326a7d30f9b888d825c68d45f7cc3fad919ca763
OPENCLAW_CONFIG_DIR=/var/www/openclaw
OPENCLAW_WORKSPACE_DIR=/var/www/openclaw/workspace
```

### 4.2. Gmail (OAuth)

**Profissional (Mail-Pro):**
- `GMAIL_PROFESSIONAL_CLIENT_ID=[REDACTED]`
- `GMAIL_PROFESSIONAL_CLIENT_SECRET=[REDACTED]`
- `GMAIL_PROFESSIONAL_REFRESH_TOKEN=[REDACTED]`
- Caixa: `rafael.pereira@smartenvios.com`

**Pessoal (Mail-Person):**
- `GMAIL_PERSONAL_CLIENT_ID=[REDACTED]`
- `GMAIL_PERSONAL_CLIENT_SECRET=[REDACTED]`
- `GMAIL_PERSONAL_REFRESH_TOKEN=[REDACTED]`
- Caixa: `rafael.silva.pereira10@gmail.com`

### 4.3. Notion

**SmartEnvios:**
- `NOTION_SMARTENVIOS_API_KEY=[REDACTED]`
- `NOTION_DATABASE_ID_SMARTENVIOS=[REDACTED]`

**Pessoal:**
- `NOTION_PERSONAL_API_KEY=[REDACTED]`
- `NOTION_DATABASE_ID_PERSONAL=[REDACTED]`

**Canper:**
- `NOTION_CANPER_API_KEY=[REDACTED]`
- `NOTION_DATABASE_ID_CANPER=[REDACTED]`

### 4.4. Modelos de IA

- `OPENAI_API_KEY=sk-proj-...`
- `ANTHROPIC_API_KEY=sk-ant-api03-...`
- `GEMINI_API_KEY=AIzaSyDOx9C8-...`
- `GROK_API_KEY=[REDACTED]`

### 4.5. SmartEnvios MCP

- `SMARTENVIOS_MCP_URL=https://staging.smartenvios.tec.br/mcp`
- `SMARTENVIOS_MCP_EMAIL=rafael.pereira@smartenvios.com`
- `SMARTENVIOS_MCP_PASSWORD=[REDACTED]`

### 4.6. Outras APIs

- `DISCORD_BOT_TOKEN=[REDACTED]`
- `BRAVE_API_KEY=[REDACTED]`
- `SAG_API_KEY=[REDACTED]`
- `GOPLACES_API_KEY=[REDACTED]`

---

## 5. Arquitetura de Agentes

### 5.1. Main (Presidente)

**Papel:** Recebe demandas e cria cards no Notion em `Aguardando`.

**Canais:** Discord (DM), WhatsApp, WebChat

**Função padrão (Notion):**
1. Criar card com propriedades:
   - **Status:** `Aguardando`
   - **Tipo:** `OpenClaw`
   - **Solicitante:** `Rafael Pereira`
   - **Agente:** diretor responsável (Tech, Pessoal, Negócios)
2. Aplicar inteligência de roteamento:
   - Identificar tipo de tarefa e especialista ideal
   - Atribuir card ao diretor correto para esse especialista
3. Escrever descrição **funcional** no card (sem detalhamento técnico)

**Regra de profundidade da descrição:**
- **DEVE incluir:** demanda funcional, domínio/área, objetivo em 1-2 frases, critérios de conclusão funcionais, contexto relevante
- **NÃO deve incluir:** passos técnicos, arquitetura, scripts/comandos, instruções de código

**Revisão contínua:** Ler cards `Tipo OpenClaw` em `Concluído`, comparar com esperado, juntar feedback e melhorar instruções/templates/KNOWLEDGE/fluxos.

**Roteamento DM/Canais:**
- **DM:** encaminhadas para agente `main`, respondidas apenas para o utilizador
- **Canais Discord:** menções `@1439351480514646087` ou palavra "einstein" → agente `einstein`

### 5.2. Diretores (3)

**Mapeamento diretor → Notion/skill:**
- **Diretor Tech SmartEnvios** → `notion` (`NOTION_SMARTENVIOS_API_KEY`)
- **Diretor Pessoal** → `notion-personal` (`NOTION_PERSONAL_API_KEY`)
- **Diretor Negócios** → `notion-canper` (`NOTION_CANPER_API_KEY`)

**Função padrão (Notion):**
1. Criar ou captar e atualizar card com propriedades:
   - **Status:** `Priorizado`
   - **Tipo:** `OpenClaw`
   - **Solicitante:** `Rafael Pereira`
   - **Agente:** especialista responsável pela execução (Mail-Pro, Mail-Person, etc.)
2. Aplicar inteligência de roteamento:
   - Identificar especialista adequado para execução
   - Responsabilizar especialista correto no campo **Agente**
3. Escrever descrição **técnica completa** para o especialista

**Pontuais (ad hoc):**
- Cron sugerido: **a cada 1 hora** (acionável manualmente)
- Captam cards em `Aguardando` que exigem análise/planejamento
- Devem: entender pedido, criar plano detalhado na descrição, mover para `Priorizado`, trocar `Agente` para especialista adequado, garantir `Tipo = OpenClaw`

**Rotinas:**
- Cron sugerido: **a cada 30 minutos**
- **Diretor Tech** e **Diretor Pessoal** têm cron rotineiro que:
  - Cria cards no Notion em status `Priorizado`
  - Atribui `Agente` = `Mail-Pro` (Diretor Tech) ou `Agente` = `Mail-Person` (Diretor Pessoal)
  - Preenche descrição com objetivo claro da tarefa (especialmente para atividade recorrente de gestão de e-mail)

**Diretor de Negócios:**
- Enquanto especialistas dedicados não existem, normaliza cards para `Priorizado` com `Agente` = especialista de negócios alvo (quando existir) ou `Tech` para execução técnica temporária

### 5.3. Especialistas

**Cron sugerido:** **a cada 15 minutos**

**Fluxo genérico:**
1. Captar cards em `Priorizado` cujo `Agente` seja eles
2. Mover para `Em andamento`
3. Ler a descrição do card (o que fazer, critérios de conclusão, Notion/recurso)
4. **Planejar a execução** (passos, dependências, resultado esperado)
5. Executar exatamente conforme descrição
6. **Durante a execução:** Inserir **comentários incrementais no card do Notion** (máximo 300 caracteres cada) mostrando: etapa atual, progresso, o que foi feito, o que pretende fazer a seguir
7. Registrar resultado no card (descrição/comentários)
8. Enviar status report no Discord e WhatsApp (quando aplicável)
9. Mover para `Concluído`

**Função padrão (Notion):**
1. Atualizar **Status** para `Em andamento`
2. Executar atividade conforme descrição do card
3. Publicar **comentários incrementais** durante execução (máx. 300 caracteres)
4. Publicar **comentário final organizado** no Notion com tudo que foi realizado
5. Atualizar **Status** para `Concluído`

**Template de comentário final:**
```markdown
🚀 UPGRADE: [Título da entrega] ([AAAA-MM-DD HH:mm GMT-3])

Novo sistema de análise automática:

✅ [Melhoria 1]
✅ [Melhoria 2]
✅ [Melhoria 3]

📊 Capacidades:
- [Capacidade 1]
- [Capacidade 2]

🎯 Ações por score:
- draft (50+): Criar rascunho contextualizado
- review (20-49): Revisar e decidir
- label (0-19): Apenas labelar
- ignore (<0): Auto-reply, arquivar

Documentação: [caminho(s) de documentação]
Commits: [hash1], [hash2]
```

#### 5.3.1. Mail-Pro

**Agente:** propriedade do card = `Mail-Pro`

**Orientação:** Diretor Tech SmartEnvios (contexto profissional)

**Uso:** tarefas de e-mail profissional (SmartEnvios)

**Caixa:** `rafael.pereira@smartenvios.com`

**Credenciais:** `.env` → `GMAIL_PROFESSIONAL_CLIENT_ID`, `GMAIL_PROFESSIONAL_CLIENT_SECRET`, `GMAIL_PROFESSIONAL_REFRESH_TOKEN`

**Responsabilidades da rotina:**
1. Buscar e-mails não lidos
2. Ler com contexto completo da conversa (thread/histórico)
3. Classificar prioridade e necessidade de ação
4. Criar rascunho contextualizado para e-mails importantes
5. Arquivar e-mails após processamento
6. Gerir labels com reuso inteligente (verificar se existe antes de criar):
   - `Mail-Pro-Aguardando`
   - `Mail-Pro-BaixoValor`
   - `Mail-Pro-Importante`
7. Aprendizado contínuo com histórico de e-mails respondidos (responder vs arquivar vs ignorar)

**Notion:** usa `notion` (SmartEnvios) por padrão

#### 5.3.2. Mail-Person

**Agente:** propriedade do card = `Mail-Person`

**Orientação:** Diretor Pessoal (contexto pessoal)

**Uso:** tarefas de e-mail pessoal

**Caixa:** `rafael.silva.pereira10@gmail.com`

**Credenciais:** `.env` → `GMAIL_PERSONAL_CLIENT_ID`, `GMAIL_PERSONAL_CLIENT_SECRET`, `GMAIL_PERSONAL_REFRESH_TOKEN`

**Responsabilidades da rotina:** (mesma lógica do Mail-Pro)
- Labels: `Mail-Person-Aguardando`, `Mail-Person-BaixoValor`, `Mail-Person-Importante`

**Notion:** usa `notion-personal` por padrão

### 5.4. Einstein (SmartEnvios Support)

**Agente ID:** `einstein`

**Workspace:** `/var/www/openclaw/workspace/agents/einstein`

**Papel:** Responder dúvidas sobre SmartEnvios em canais Discord

**Gatilho Discord:** menção `@1439351480514646087` ou palavra "einstein"

**Canais:** 100% Discord (todas as mensagens, canais, DMs)

**Restrições:**
- **Bloqueadas:** `exec`, `gateway`, `sessions_*`, `subagents`, `cron`, `write`, `edit`, `process`, `nodes`, `browser`, `canvas`
- **Permitidas:** `read`, `web_search`, `web_fetch`, `message`

**Sandbox:** `workspaceAccess: "ro"` (read-only)

**Regras:**
- Não deve abrir ou expor ecossistema de agentes nem OpenClaw
- Manter restrições de segurança
- Registrar aprendizados em KNOWLEDGE/base do agente

**Fontes de informação SmartEnvios:**
- Notion SmartEnvios (via `NOTION_SMARTENVIOS_API_KEY`)
- Base pública: `https://smartenvios.zendesk.com/hc/pt-br`
- Playlists YouTube SmartEnvios (4 playlists)
- MCP SmartEnvios: `https://staging.smartenvios.tec.br/mcp`

**Enriquecimento:**
- Adicionar FAQs em `agents/einstein/KNOWLEDGE.md`
- Adicionar exemplos em `agents/einstein/examples/`
- Documentar APIs em `agents/einstein/API_REFERENCE.md`

### 5.5. Especialista Dúvidas SmartEnvios

**Canal:** WhatsApp e Discord

**Gatilho obrigatório:** `Dúvida: {{texto}}`

**Regra:** Fora desse formato, não deve assumir que a mensagem é para ele

**Ao receber a dúvida:**
- Consultar bases, MCP, documentos, APIs e sites relevantes
- Responder objetivamente
- Registrar aprendizados para evolução contínua (KNOWLEDGE/base própria)

**Regra de encaminhamento:**
- Rafael Pereira pode interagir normalmente
- Para outros utilizadores, se o Presidente identificar intenção de tirar dúvida sem prefixo, deve orientar: **use `Dúvida: {{texto}}`**

**Esteira Einstein → Diretor Tech → Engenheiro Backend:**
Quando Einstein não conseguir responder por limitação técnica:
1. Criar card em `Aguardando` com `Tipo: OpenClaw`, `Solicitante: Rafael Pereira`, `Agente: Tech`
2. Diretor Tech detalha solução/plano técnico e muda para `Priorizado` com `Agente: Engenheiro Backend`
3. Engenheiro Backend executa melhoria no repositório MCP/API, documenta evidências e conclui

### 5.6. Agente de Governança

**Papel:** Garantir continuidade operacional de todos os crons e agentes

**Cron:** `Governança - health check 5min` (ID: `6b70fa44-66ac-4665-bad3-00d6122f9da1`)

**Frequência:** a cada 5 minutos

**Script:** `scripts/governance-check.sh`

**O que faz:**
1. **Health check do gateway** — se DOWN, reinicia automaticamente
2. **Detecta crons com erros consecutivos** (>= 2) — reseta sessão e re-habilita
3. **Detecta crons travados** (running > 20min) — registra alerta
4. **Verifica cards em `Em andamento` há muito tempo** (>20min sem atividade):
   - `Agente=Mail-Pro` → força execução do cron `b3c678e4`
   - `Agente=Mail-Person` → força execução do cron `568c5ad9`
   - Outros agentes (>30min) → registra alerta para intervenção manual
5. **Registra incidentes** em `memory/YYYY-MM-DD.md`

**O que NÃO faz:**
- Não cria cards no Notion
- Não move cards de status
- Não interfere na lógica de negócio dos agentes

**Responsabilidades (planejadas):**
- Verificar saúde constantemente (gateway, agentes, crons, conectividade)
- Garantir conclusão de execuções (cards travados, crons não executados)
- Contingência para evitar crashes (detectar falhas antes de causar interrupção)
- Evitar ficar descoberto (lacunas operacionais)

### 5.7. Agente de Otimização e Performance

**Papel:** Análise e melhoria contínua

**Cron sugerido:** diariamente (após fim do dia ou início do dia seguinte)

**Responsabilidades:**
1. **Análise diária de logs:**
   - Processar logs do dia anterior (gateway, agentes, crons, operações)
   - Identificar padrões: erros recorrentes, operações lentas, timeouts, falhas de conectividade
   - Mapear gargalos técnicos por agente, operação ou fluxo

2. **Análise de fluxo e instruções:**
   - Revisar descrições de cards, templates, instruções em FLUXO_AGENTES, AGENTS.md, KNOWLEDGE.md
   - Identificar sobreposições (instruções contraditórias ou redundantes)
   - Identificar incoerências (instruções que conflitam entre documentos ou versões)
   - Propor simplificações e melhorias de clareza

3. **Otimizações propostas/implementadas:**
   - Ajustar instruções em documentos para eliminar ambiguidade
   - Sugerir melhorias em templates de descrição de cards
   - Otimizar lógica de decisão (ex.: quando Mail-Pro deve criar rascunho vs apenas arquivar)
   - Documentar aprendizados e padrões otimizados

4. **Integração com Governança:**
   - Ler relatórios/incidentes documentados pela Governança
   - Focar otimizações nos pontos que mais causaram trabalho para a Governança
   - Objetivo: reduzir progressivamente a carga de trabalho da Governança através de otimizações preventivas

**Parceria com Governança:**
- **Governança:** garante que o processo seja executado independente do erro (reativo)
- **Otimizador:** pega os gargalos que fizeram a Governança ter trabalho e otimiza para que não aconteçam novamente (preventivo)
- **Objetivo de longo prazo:** com o tempo, fluxos mais antigos devem dar menos trabalho para a Governança garantir

---

## 6. Fluxos Operacionais

### 6.1. Fluxo Notion (Cards)

**Status:** `Aguardando` → `Priorizado` → `Em andamento` → `Concluído`

**Tipo:** `OpenClaw` (obrigatório)

**Propriedade chave:** `Agente`

**Regra de escopo e deduplicação por agente:**

| Agente | Capta de | Checa duplicidade em | Move para |
|--------|----------|---------------------|-----------|
| **Presidente** | — (cria) | `Aguardando` | `Aguardando` |
| **Diretor** | `Aguardando` | `Priorizado` | `Priorizado` |
| **Especialista** | `Priorizado` | `Em andamento` | `Em andamento` → `Concluído` |

**Regra de duplicidade — chave dupla: Assunto + Agente**
- Um card é considerado duplicado se já existir outro com o **mesmo título** e o **mesmo Agente** no status de saída do agente
- Se existir 1 card em `Aguardando` e 0 em `Priorizado` (mesmo assunto+agente), o diretor **deve priorizar**
- Se existir 1 em `Aguardando` e 1 em `Priorizado` (mesmo assunto+agente), o diretor **espera o próximo ciclo** para não duplicar
- Mesma lógica para especialistas: se já existir 1 em `Em andamento` (mesmo assunto+agente), esperar o próximo ciclo

**O que cada agente NÃO consulta:**
- Presidente: não consulta `Priorizado`, `Em andamento` nem `Concluído`
- Diretor: não consulta `Em andamento` nem `Concluído`
- Especialista: não consulta `Aguardando` nem `Concluído`

### 6.2. Template de Descrição (Diretor)

```markdown
## Contexto
[Origem do pedido e objetivo em uma frase.]

## O que fazer (passos)
1. ...
2. ...
3. ...

## Critérios de conclusão
- ...

## Notion / recurso
- Skill: notion | notion-personal | notion-canper
- [IDs ou links]

## Checklist obrigatório (strict)
- [ ] Status inicial em Priorizado
- [ ] Agente correto (Mail-Pro ou Mail-Person)
- [ ] Objetivo e escopo explícitos
- [ ] Passos executáveis sem ambiguidade
- [ ] Regra de labels (reusar antes de criar)
- [ ] Regra de saída (comunicar no Discord/WhatsApp + mover para Concluído)
```

### 6.3. Padrão Reutilizável de Propriedades

Ao criar cards de rotina/melhoria, usar padrão base:
- **Status:** `Aguardando`
- **Tipo:** `OpenClaw`
- **Solicitante:** `Rafael Pereira`
- **Agente:** conforme responsável inicial (`Tech`, `Mail-Pro`, `Mail-Person`, etc.)

Template oficial: `templates/notion-card-openclaw.md`

### 6.4. Regra API-first

- Todo acesso operacional deve ser via **API/MCP**
- Zendesk também deve ser consumido via MCP (API)
- Exceção permitida: painel da base de conhecimento Zendesk para consulta visual quando necessário

---

## 7. Skills e Integrações

### 7.1. Notion (3 workspaces)

**1. `notion` (SmartEnvios - Default)**
- Workspace: SmartEnvios
- API Key: `${NOTION_SMARTENVIOS_API_KEY}`
- Database ID: `adec12e735dc41a3bb7c274b287f3a10`
- Uso: Diretor Tech SmartEnvios, Mail-Pro

**2. `notion-personal` (Personal)**
- Workspace: Personal
- API Key: `${NOTION_PERSONAL_API_KEY}`
- Database ID: `bfcbe7a7a3a745489e605e0762af12a9`
- Uso: Diretor Pessoal, Mail-Person

**3. `notion-canper` (Canper)**
- Workspace: Canper
- API Key: `${NOTION_CANPER_API_KEY}`
- Database ID: `14abf9163c9680ff822bc2e32f6bec4b`
- Uso: Diretor Negócios

### 7.2. Gmail Scripts

**Localização:** `/var/www/openclaw/workspace/scripts/gmail/`

**Profiles:**
- **pro** → `rafael.pereira@smartenvios.com` (Mail-Pro)
- **personal** → `rafael.silva.pereira10@gmail.com` (Mail-Person)

**Scripts principais:**
- `gmail.sh` — API wrapper (auth, list, get, thread, labels, draft-create, archive)
- `triage.sh` — Triagem de não lidos com metadata estruturada (limite: 100 emails)
- `analyze.sh` — Análise inteligente (filtra auto-replies, prioriza menções diretas, contexto de thread)
- `workflow.sh` — Workflow completo (triagem + análise + priorização, limite: 100 emails)
- `unsubscribe.sh` — Detecta e executa unsubscribe de emails promocionais
- `cleanup-promotions.sh` — Cleanup automático de emails promocionais/sociais com unsubscribe

**Uso rápido (workflow inteligente):**
```bash
# Processar emails com priorização e contexto
./scripts/gmail/workflow.sh pro 20

# Output: emails ordenados por score, com flags:
# - needsDraft: score >= 50 (menção direta + urgente)
# - needsReview: score >= 20 (keywords de ação)
# - needsLabel: score >= 0 (baixo valor)
# - shouldIgnore: score < 0 (auto-replies)
```

**Documentação completa:**
- `scripts/gmail/README.md` - API reference
- `scripts/gmail/AGENT_WORKFLOW.md` - Workflow para especialistas Mail-Pro/Person

### 7.3. SmartEnvios MCP

**Script:** `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh`

**Credenciais no `.env`:**
- `SMARTENVIOS_MCP_URL=https://staging.smartenvios.tec.br/mcp`
- `SMARTENVIOS_MCP_EMAIL=rafael.pereira@smartenvios.com`
- `SMARTENVIOS_MCP_PASSWORD=ffbnVK_Z4:X3jA.`

**Estado local:** `workspace/.state/smartenvios_mcp_session_token`

**Uso:**
```bash
./scripts/smartenvios-mcp.sh login
./scripts/smartenvios-mcp.sh tools
./scripts/smartenvios-mcp.sh call cep_lookup '{"cep":"14020510"}'
```

### 7.4. Outras Skills

- **nano-banana-pro:** Gemini AI integration (`${GEMINI_API_KEY}`)
- **sag:** SAG API integration (`${SAG_API_KEY}`)

---

## 8. Padrões e Regras

### 8.1. Logging Obrigatório

**Princípio:** Logging obrigatório em todos os fluxos — nenhum fluxo silencioso permitido.

**Regras:**
- Usar `createSubsystemLogger(subsystem)` em módulos com domínio claro
- Usar `logInfo` / `logWarn` / `logError` / `logDebug` de `src/logger.ts` nos demais casos
- Nunca usar `console.log` em código de produção
- Registrar início e fim de toda operação significativa (com `durationMs`)
- Registrar todos os erros em nível ERROR com `requestId` e `errorCode`
- Registrar todas as decisões de roteamento e seleção de agente
- Nunca registrar tokens, senhas, PII ou documentos sensíveis
- Redactar dados sensíveis antes de logar

**Referência técnica:** `docs/development/LOGGING_AND_RULES.md`

### 8.2. Autonomia e Resiliência

**Autonomia:**
- Identificar os próprios erros
- Corrigir a rota (sem pedir autorização para mudanças não destrutivas)
- Documentar lições para não repetir

**Resiliência:**
- Antes de declarar bloqueio, tentar o fallback óbvio (ex.: buscar usuários/IDs via API, repetir ação com credencial alternativa, checar logs)
- Ao manipular Notion, sempre que um campo `people`/`relation` falhar no preenchimento direto, consultar `/v1/users` ou `/v1/search` para capturar o ID correto e tentar novamente
- Somente após esgotar as rotas previstas registrar pendência no card

**Referência operativa:** `AGENTS.md → Autonomia – erros, correção e documentação`

### 8.3. Comentários Incrementais

**Durante a execução:** Especialistas devem inserir comentários incrementais no card do Notion (máximo 300 caracteres cada) mostrando:
- Etapa atual
- Progresso
- O que foi feito
- O que pretende fazer a seguir

**Exemplos:**
- `📧 Lendo e-mails não lidos (15 encontrados)`
- `🔍 Analisando thread completa do e-mail X`
- `✍️ Criando rascunho para e-mail importante`
- `🏷️ Aplicando labels (Mail-Pro-Importante)`
- `📦 Arquivando e-mails processados`

**Benefício:** Evita ficar "cego" do progresso — é possível ver em tempo real em que etapa está, o que avançou e o que pretende fazer.

### 8.4. Labels com Reuso Inteligente

**Regra:** Antes de aplicar qualquer label, verificar se já existe; se existir, reutilizar; se não existir, criar automaticamente.

**Labels Mail-Pro:**
- `Mail-Pro-Aguardando`
- `Mail-Pro-BaixoValor`
- `Mail-Pro-Importante`

**Labels Mail-Person:**
- `Mail-Person-Aguardando`
- `Mail-Person-BaixoValor`
- `Mail-Person-Importante`

---

## 9. Referências e Documentação

### 9.1. Documentos Principais

- **FLUXO_AGENTES.md** — Fluxo operacional completo Notion (Presidente, Diretores, Especialistas)
- **AGENTS.md** — Regras e padrões dos agentes, autonomia, resiliência
- **PLANO_PROJETO.md** — Plano de projeto (logging obrigatório)
- **TOOLS.md** — Ferramentas e skills disponíveis
- **NOTION.md** — Workspaces Notion configurados
- **KNOWLEDGE.md** — Conhecimento histórico e padrões
- **SETUP_COMPLETO.md** — Este documento (referência única)

### 9.2. Documentação Técnica

- **docs/development/LOGGING_AND_RULES.md** — Regras técnicas de logging
- **scripts/gmail/README.md** — API reference Gmail
- **scripts/gmail/AGENT_WORKFLOW.md** — Workflow para especialistas Mail-Pro/Person
- **agents/einstein/README.md** — Configuração Einstein
- **agents/einstein/ENRICHMENT_GUIDE.md** — Como enriquecer Einstein

### 9.3. Templates

- **templates/notion-card-openclaw.md** — Template oficial para cards OpenClaw

### 9.4. Fontes SmartEnvios (Einstein)

- **Notion SmartEnvios:** Processos, base de conhecimento (via API)
- **Base pública:** `https://smartenvios.zendesk.com/hc/pt-br`
- **Playlists YouTube:** 4 playlists SmartEnvios
- **MCP:** `https://staging.smartenvios.tec.br/mcp`

---

## 10. Checklist de Setup

### 10.1. Configuração Inicial

- [ ] Workspace criado em `/var/www/openclaw/workspace`
- [ ] `openclaw.json` configurado com agentes (main, einstein)
- [ ] `.env` configurado com todas as credenciais
- [ ] Gateway OpenClaw rodando e acessível
- [ ] Logs configurados em `/var/www/openclaw/logs/gateway.log`

### 10.2. Skills e Integrações

- [ ] Notion SmartEnvios configurado (`notion`)
- [ ] Notion Pessoal configurado (`notion-personal`)
- [ ] Notion Canper configurado (`notion-canper`)
- [ ] Gmail OAuth configurado (profissional e pessoal)
- [ ] SmartEnvios MCP configurado
- [ ] Discord bot token configurado
- [ ] WhatsApp configurado (allowlist)

### 10.3. Agentes

- [ ] Main (Presidente) operacional
- [ ] Diretores configurados (Tech, Pessoal, Negócios)
- [ ] Mail-Pro configurado e testado
- [ ] Mail-Person configurado e testado
- [ ] Einstein configurado e testado (gatilho Discord)
- [ ] Agente de Governança configurado (cron 5min)
- [ ] Agente de Otimização e Performance planejado

### 10.4. Crons

- [ ] Cron Diretor Tech (rotinas Mail-Pro)
- [ ] Cron Diretor Pessoal (rotinas Mail-Person)
- [ ] Cron Governança (health check 5min)
- [ ] Cron Otimização (diário - planejado)

### 10.5. Documentação

- [ ] FLUXO_AGENTES.md atualizado
- [ ] AGENTS.md atualizado
- [ ] PLANO_PROJETO.md atualizado
- [ ] TOOLS.md atualizado
- [ ] SETUP_COMPLETO.md criado (este documento)

---

## 11. Manutenção e Evolução

### 11.1. Monitoramento

- **Logs:** `tail -f /var/www/openclaw/logs/gateway.log`
- **Governança:** verifica saúde a cada 5 minutos
- **Otimização:** analisa logs diariamente

### 11.2. Atualizações

- Documentar mudanças em `memory/YYYY-MM-DD.md`
- Atualizar `SETUP_COMPLETO.md` quando houver mudanças significativas
- Revisar e atualizar templates quando necessário

### 11.3. Evolução Contínua

- **Governança:** garante execução mesmo com erros
- **Otimização:** elimina gargalos identificados pela Governança
- **Objetivo:** reduzir progressivamente a carga de trabalho da Governança através de otimizações preventivas

---

**Fim do documento**
