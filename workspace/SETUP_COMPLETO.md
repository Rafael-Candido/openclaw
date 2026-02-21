# Setup Completo do Ambiente OpenClaw

**Documento único de referência** consolidando todo o setup, arquitetura, fluxos operacionais e implementações do ambiente OpenClaw.

**Última documentação: 2026-02-20 22:52**

**Última atualização:** 2026-02-21 (documentação alinhada ao openclaw.json: agentes, canais, Einstein model/tools, bindings Discord)

---

## 0. Patch Operacional (2026-02-20)

Esta seção sobrescreve pontos antigos deste documento quando houver divergência.

### 0.1. Modelos e providers validados

- **DeepSeek (novo):**
  - Provider custom em `openclaw.json > models.providers.deepseek`
  - `deepseek/deepseek-chat`
  - `deepseek/deepseek-reasoner`
  - Credencial: `DEEP_API_KEY`

- **Google Gemini:**
  - Modelo atualizado para `google/gemini-3-pro-preview` (alias `Google Gemini 3 Pro`)
  - Validação direta de API com sucesso em `gemini-2.5-flash` (`generateContent`)
  - Observação: referências a Gemini `1.5` neste documento são históricas e podem falhar com 404

- **xAI/Grok:**
  - Variável obrigatória no runtime: `XAI_API_KEY`
  - `GROK_API_KEY` pode existir por compatibilidade, mas não substitui `XAI_API_KEY`
  - Endpoint oficial `POST /v1/responses` validado com `grok-4-1-fast-reasoning`

### 0.2. Governança reforçada

`scripts/governance-check.sh` passou a incluir:
- limpeza de locks de sessão obsoletos (`*.lock`) em main, einstein, eng-smartenvios, eng-prompt (MAX_LOCK_MIN=5min)
- detecção de pressão de modelos no log (`rate limit`, `cooldown`, `session file locked`)
- reinício preventivo do gateway em saturação recorrente

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
│   │   ├── einstein/          # Einstein: KNOWLEDGE.md (5 fontes), knowledge/{notion,youtube,github,zendesk,jira}
│   │   ├── eng-prompt/        # Engenheiro de Prompt (BOOTSTRAP, IDENTITY, SOUL, TOOLS, USER)
│   │   ├── eng-smartenvios/   # Engenheiro SmartEnvios (BOOTSTRAP, IDENTITY, SOUL, TOOLS, USER)
│   │   └── backend-engineer/  # Engenheiro Backend (legado)
│   ├── scripts/
│   │   ├── gmail/             # Scripts Gmail (triagem, workflow)
│   │   ├── notion-helper.sh   # Helper Notion API (query, update-status, comment, create-card, etc.)
│   │   ├── notion-canper-*.py # Scripts Notion Canper (query, schema, status, update-card, check-*)
│   │   ├── add-comment.py     # Ad-hoc: comentário em card Notion (NOTION_PERSONAL_API_KEY)
│   │   ├── export_einstein_base*.py  # Export base SmartEnvios → einstein/knowledge
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
- Modelo: `openai/gpt-5.1-codex` (primary), fallbacks: GPT-4 Turbo, DeepSeek Chat, Claude Sonnet 4.6, Claude Opus 4.6

**Engenheiro SmartEnvios:**
- ID: `eng-smartenvios`
- Workspace: `/var/www/openclaw/workspace/agents/eng-smartenvios`
- Papel: fullstack — repos SmartEnvios em `/var/www/`, recebe demandas do Diretor Tech (bugs, melhorias, MCP). GitHub https://github.com/SmartEnvios
- Modelo: `google/gemini-3-pro-preview` (primary), fallbacks: Gemini 2.5 Pro, Claude Sonnet, GPT-4 Turbo, DeepSeek
- Skills: `notion` (Notion SmartEnvios)
- Sandbox: `off`

**Engenheiro de Prompt:**
- ID: `eng-prompt`
- Workspace: `/var/www/openclaw/workspace/agents/eng-prompt`
- Papel: manutenção e evolução da estrutura OpenClaw — agentes, prompts, docs. Reporta ao Diretor Pessoal. Otimizador e Governança criam cards para ele. GitHub https://github.com/Rafael-Candido
- Modelo: `google/gemini-3-pro-preview` (primary), fallbacks: Gemini 2.5 Pro, Claude Sonnet, GPT-4 Turbo, DeepSeek
- Skills: `notion-personal` (Notion Pessoal)
- Sandbox: `off`

**Einstein (SmartEnvios Support):**
- ID: `einstein`
- Workspace: `/var/www/openclaw/workspace/agents/einstein`
- Modelo: `xai/grok-4-1-fast-non-reasoning` (primary), fallbacks: Grok 3 Mini, Grok 3, DeepSeek Chat, GPT-4 Turbo, Claude Sonnet 4.6, Claude Opus 4.6, Grok Beta
- **Gatilho Discord:** menção `@1439351480514646087` ou palavra "einstein" (`groupChat.mentionPatterns`)
- **Tools permitidas:** `read`, `write`, `edit`, `web_search`, `web_fetch`, `message`, `exec`, `sessions_history`
- **Tools bloqueadas:** `gateway`, `sessions_send`, `sessions_spawn`, `sessions_list`, `subagents`, `cron`, `process`, `nodes`, `browser`, `canvas`
- **Sandbox:** `mode: "off"` (exec permitido para MCP/scripts, ex.: `scripts/smartenvios-mcp.sh`)

### 3.2. Canais Configurados

**Discord:**
- `groupPolicy: "open"`
- **Bindings:** canal `discord` → agente `einstein` (todas as mensagens Discord são atendidas pelo Einstein)
- `dmPolicy: "allowlist"` com `allowFrom: ["932709376790233088"]` — DMs aceitas apenas desse utilizador
- Menções `@1439351480514646087` ou "einstein" acionam o Einstein em grupos

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
- `DEEP_API_KEY=...` (DeepSeek; usado em `models.providers.deepseek`)
- `XAI_API_KEY=...` ou `GROK_API_KEY=...` (xAI/Grok; Einstein e fallbacks usam modelos `xai/*`)

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

**Regra de profundidade da descrição (CRÍTICO):**
- O Presidente deve escrever descrição **funcional e clara**, mas **sem detalhamento técnico**
- Os diretores agora operam com cron **generalista** — captam qualquer card `Aguardando` do domínio deles
- Por isso, a descrição funcional do Presidente é a **única fonte de contexto** para o diretor entender, rotear e detalhar tecnicamente
- **DEVE incluir:** demanda funcional, domínio/área, objetivo em 1-2 frases, critérios de conclusão funcionais, contexto relevante
- **NÃO deve incluir:** passos técnicos, arquitetura, scripts/comandos, instruções de código, nome de ferramentas internas ou paths de scripts
- **Quem detalha tecnicamente é o Diretor** ao captar o card e mover para `Priorizado`

**Revisão contínua:** Ler cards `Tipo OpenClaw` em `Concluído`, comparar com esperado, juntar feedback e melhorar instruções/templates/KNOWLEDGE/fluxos.

**Roteamento DM/Canais:**
- **DM WhatsApp/WebChat:** agente `main`, respondidas apenas para o utilizador
- **Discord:** todo o canal está ligado ao agente `einstein` (bindings); menções `@1439351480514646087` ou "einstein" acionam resposta em grupos; DMs Discord aceitas apenas de `allowFrom: 932709376790233088`

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
- **Função padrão (Notion):** Enquanto especialistas dedicados não existem:
  1. Captar demandas de negócio e normalizar o card para `Priorizado` com `Tipo: OpenClaw`, `Solicitante: Rafael Pereira`
  2. Atribuir `Agente` = especialista de negócios alvo (quando existir) ou `Tech` para execução técnica temporária
  3. Escrever descrição técnica/funcional acionável para execução
  4. Registrar no card qual especialista de negócios será o responsável definitivo assim que for criado
- Quando os especialistas de Negócios forem criados: substituir o `Agente` temporário pelo especialista correto, mantendo o mesmo padrão de lifecycle (`Priorizado` → `Em andamento` → `Concluído`)

**Roteamento recomendado (Diretor → Especialista):**

| Tipo de tarefa | Diretor | Especialista (Agente) |
|----------------|---------|------------------------|
| Backend/API/MCP | `Tech` | `Engenheiro Backend` |
| E-mail profissional | `Tech` | `Mail-Pro` |
| E-mail pessoal | `Diretor Pessoal` | `Mail-Person` |
| Negócios (antes dos especialistas) | `Diretor Negócios` | `Tech` (temporário) |
| Negócios (após criação dos especialistas) | `Diretor Negócios` | `[Especialista de Negócios]` |

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

**Modelo (openclaw.json):** `xai/grok-4-1-fast-non-reasoning` (primary), fallbacks Grok 3 Mini, Grok 3, DeepSeek, GPT-4 Turbo, Claude Sonnet/Opus, Grok Beta

**Gatilho Discord:** menção `@1439351480514646087` ou palavra "einstein"

**Canais:** 100% Discord (bindings: canal discord → agente einstein)

**Tools (openclaw.json):**
- **Permitidas:** `read`, `write`, `edit`, `web_search`, `web_fetch`, `message`, `exec`, `sessions_history`
- **Bloqueadas:** `gateway`, `sessions_send`, `sessions_spawn`, `sessions_list`, `subagents`, `cron`, `process`, `nodes`, `browser`, `canvas`

**Sandbox:** `mode: "off"` — exec permitido (ex.: script MCP SmartEnvios)

**Regras:**
- Não deve abrir ou expor ecossistema de agentes nem OpenClaw
- Manter restrições de segurança
- Registrar aprendizados em KNOWLEDGE/base do agente

**Ferramentas Operacionais (agents/einstein/AGENTS.md):**

**SmartEnvios MCP (USAR SEMPRE QUE POSSÍVEL):**
- Acesso ao MCP SmartEnvios via exec para: cotações de frete (`smartenvios_quote_freight`), consulta de CEP (`cep_lookup`), qualquer operação que o MCP suporte
- Script: `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh`
- **Regra:** se alguém pedir cotação ou operação SmartEnvios, **execute via MCP** em vez de apenas orientar como fazer manualmente

**Escalonamento para Notion (quando não conseguir resolver):**
Quando Einstein não conseguir resolver algo (falta de acesso, limitação técnica, precisa de implementação):
1. Criar card no Notion SmartEnvios com `Status: Aguardando`, `Tipo: OpenClaw`, `Solicitante: Rafael Pereira`, `Agente: Tech`
2. Descrição funcional no card: o que foi pedido, por que não conseguiu resolver, o que precisa ser feito para resolver
3. Informar o solicitante que criou a atividade e que o Diretor Tech vai priorizar
- Database Notion SmartEnvios: `adec12e735dc41a3bb7c274b287f3a10`
- API Key: usar skill `notion` ou `$NOTION_SMARTENVIOS_API_KEY`

**Comportamento em Group Chats:**
- **Know When to Speak:** responder quando mencionado diretamente, quando pode adicionar valor genuíno, quando algo engraçado se encaixa naturalmente, quando corrigindo desinformação importante, quando resumindo quando pedido
- **Stay silent (HEARTBEAT_OK):** quando é apenas conversa casual entre humanos, quando alguém já respondeu, quando a resposta seria apenas "yeah" ou "nice", quando a conversa está fluindo bem sem você
- **React Like a Human:** usar reações emoji naturalmente (👍, ❤️, 🙌, 😂, 💀, 🤔, 💡, ✅, 👀) — uma reação por mensagem máximo
- **Evitar triple-tap:** não responder múltiplas vezes à mesma mensagem com reações diferentes

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
Quando Einstein não conseguir responder uma dúvida SmartEnvios por limitação técnica:
1. Criar card em `Aguardando` com `Tipo: OpenClaw`, `Solicitante: Rafael Pereira`, `Agente: Tech`
2. Diretor Tech detalha solução/plano técnico e muda para `Priorizado` com `Agente: Engenheiro Backend`
3. Engenheiro Backend executa melhoria no repositório MCP/API, documenta evidências e conclui

### 5.5.1. Engenheiro Backend

**Agente:** propriedade do card = `Engenheiro Backend` (ou `Backend Engineer`)

**Workspace:** `/var/www/openclaw/workspace/agents/backend-engineer`

**Papel:** Especialista em melhorias técnicas de backend para o ecossistema OpenClaw/SmartEnvios

**Foco principal:**
- MCP SmartEnvios
- Zendesk via MCP/API
- Automações API-first do fluxo Notion

**Fluxo de trabalho:**
1. Recebe card em `Priorizado` com `Agente = Engenheiro Backend`
2. Executa melhoria técnica no(s) repositório(s) alvo
3. Registra evidências no card (o que foi alterado, testes, impacto)
4. Move para `Concluído`

**Regras:**
- Priorizar acesso por API/MCP (API-first)
- Evitar fluxo manual/painel quando existir endpoint/tool disponível
- Documentar mudanças em `KNOWLEDGE.md` e evidências no card
- Nunca expor credenciais em logs/comentários

**Entrada esperada:**
- Cards em `Priorizado` com `Tipo = OpenClaw`, `Agente = Engenheiro Backend`
- Descrição técnica detalhada pelo Diretor Tech

**Saída obrigatória:**
- Atualização técnica implementada
- Evidências no card
- Status final em `Concluído`

### 5.6. Agente de Governança

**Papel:** Garantir continuidade operacional e escalonamento correto de todos os crons e agentes

**Cron:** `Governança - health check 10min` (ID: `e5bb7978-cd99-4e8d-924a-b4d42a140c1e`)

**Frequência:** a cada 10 minutos

**Script:** `scripts/governance-check.sh`

**O que faz:**
1. **Health check do gateway** — se DOWN, reinicia automaticamente
2. **Detecta crons com erros consecutivos** (>= 2) — reseta sessão e re-habilita
3. **Detecta crons travados** (running > 20min) — reseta sessão
4. **Escalonamento automático de crons** — verifica se há colisão entre crons (gap < 2min entre execuções próximas). Se detectar sobreposição, ajusta os anchors automaticamente para garantir separação mínima de 2 minutos. Isso escala com novos agentes/crons sem intervenção manual
5. **Verifica cards em `Em andamento` há muito tempo** (>20min sem atividade):
   - `Agente=Mail-Pro` → força execução do cron Mail-Pro
   - `Agente=Mail-Person` → força execução do cron Mail-Person
   - Outros agentes (>30min) → registra alerta para intervenção manual
6. **Registra incidentes** em `memory/YYYY-MM-DD.md`

**Escalonamento automático — como funciona:**
- A governança calcula o `nextRun` de cada cron habilitado, ordena por proximidade, e verifica se há gap < 2min entre consecutivos
- Se houver, desloca o anchor do cron mais tardio para manter separação mínima
- Isso significa que ao **adicionar novos agentes e crons**, a governança redistribui automaticamente — basta aumentar a periodicidade conforme o número de crons cresce para manter folga no rate limit

**Regra prática de periodicidade:**
- Até 10 crons: intervalos de 10min (especialistas) e 30min (diretores) são suficientes
- 10-15 crons: considerar intervalos de 15min e 45min
- 15+ crons: considerar intervalos de 20min e 1h, ou reduzir `maxConcurrent` para 1

**O que NÃO faz:**
- Não cria cards no Notion
- Não move cards de status
- Não interfere na lógica de negócio dos agentes

### 5.7. Agente de Otimização e Performance

**Papel:** Análise e melhoria contínua — trabalha em parceria com a Governança

**Cron:** `Otimizador - análise diária 7h` (ID: `9cb7163f-2e4e-48ed-9035-8148c77c5968`)

**Frequência:** diário às 7h (America/Sao_Paulo)

**Prompt:** `scripts/optimizer-prompt.txt`

**Parceria com Governança:**
- **Governança:** é o **bombeiro** (garante execução em tempo real)
- **Otimizador:** é o **engenheiro** (elimina a causa raiz para que a governança tenha cada vez menos trabalho)

**Fases de execução:**
1. **O que deu trabalho para a governança?**
   - Lê logs, memory, cron list → identifica erros, sessões inchadas, crons lentos, cards travados, gateway restarts
   - Para cada incidente, identifica a **causa raiz** (não apenas o sintoma)

2. **Eliminar a causa raiz:**
   - Sessão inchada → reset + análise se prompt pode ser enxuto
   - Cron lento → simplifica prompt
   - Gateway instável → aplica stagger entre crons
   - Card travado → melhora instruções do especialista
   - Instruções conflitantes → corrige documentos e prompts dos crons
   - Regras duplicadas → consolida em local único

3. **Documentar para não repetir:**
   - `KNOWLEDGE.md` → padrões definitivos com causa + fix
   - `memory/YYYY-MM-DD.md` → resumo do dia + tendência

**Objetivo de longo prazo:**
- Fluxos maduros devem gerar **zero incidentes** para a governança
- O otimizador mede isso via tendência diária (incidentes hoje vs ontem)

**O que pode fazer:**
- Resetar sessões, ajustar stagger, simplificar prompts, corrigir documentos
- Toda alteração registrada em KNOWLEDGE.md

**O que NÃO faz:**
- Não desabilita crons
- Não cria/move cards no Notion
- Não altera credenciais

---

## 6. Fluxos Operacionais

### 6.1. Fluxo Notion (Cards)

**Status:** `Aguardando` → `Priorizado` → `Em andamento` → `Concluído`

**Tipo:** `OpenClaw` (obrigatório)

**Propriedade chave:** `Agente`

**Regra de escopo e deduplicação por agente — OBRIGATÓRIO:**

Cada agente opera em **dois status**: capta do status de entrada e checa duplicidade no status de saída.

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

### 8.5. Comportamento em Group Chats (AGENTS.md)

**Know When to Speak:**
- **Responder quando:** mencionado diretamente, quando pode adicionar valor genuíno, quando algo engraçado se encaixa naturalmente, quando corrigindo desinformação importante, quando resumindo quando pedido
- **Stay silent (HEARTBEAT_OK):** quando é apenas conversa casual entre humanos, quando alguém já respondeu, quando a resposta seria apenas "yeah" ou "nice", quando a conversa está fluindo bem sem você
- **Regra humana:** Humanos em group chats não respondem a cada mensagem. Nem você deve. Qualidade > quantidade

**React Like a Human:**
- Usar reações emoji naturalmente (👍, ❤️, 🙌, 😂, 💀, 🤔, 💡, ✅, 👀)
- Reagir quando: aprecia algo mas não precisa responder, algo fez rir, acha interessante, quer reconhecer sem interromper o fluxo
- Uma reação por mensagem máximo

**Evitar triple-tap:** Não responder múltiplas vezes à mesma mensagem com reações diferentes. Uma resposta pensada vence três fragmentos.

### 8.6. Live Feedback (Main Session)

Em chat direto com o utilizador (`agent:main:main`), evitar execuções silenciosas longas.

Quando uma tarefa precisa de ferramentas ou pode levar mais de ~5-10 segundos:
- Enviar reconhecimento rápido primeiro (o que vai verificar/fazer)
- Enquanto ainda trabalha, postar atualizações de progresso curtas a cada ~20-40 segundos
- Se um passo estiver bloqueado/mais lento que esperado, dizer o que aconteceu e próxima ação
- Terminar com resultado conciso e próximo passo imediato

**Para atualizações de progresso no webchat principal**, preferir tabela compacta com percentual de conclusão:

| Etapa | Status | Conclusão |
|-------|--------|-----------|
| Diagnóstico | Em andamento | 25% |
| Ajuste de config | Pendente | 0% |
| Validação final | Pendente | 0% |

Regras: manter curto (3-6 linhas máximo), atualizar percentuais realisticamente conforme o trabalho avança. Para Discord/WhatsApp, continuar usando bullets (sem tabelas markdown).

### 8.7. Heartbeats — Ser Proativo

Quando receber um heartbeat poll, não apenas responder `HEARTBEAT_OK` sempre. Usar heartbeats produtivamente!

**Heartbeat vs Cron:**
- **Usar heartbeat quando:** múltiplas verificações podem ser agrupadas (inbox + calendário + notificações em uma vez), precisa de contexto conversacional de mensagens recentes, timing pode variar ligeiramente (~30 min está ok, não exato), quer reduzir chamadas de API combinando verificações periódicas
- **Usar cron quando:** timing exato importa ("9:00 AM sharp toda segunda"), tarefa precisa isolamento do histórico da sessão principal, quer modelo ou nível de pensamento diferente para a tarefa, lembretes one-shot ("lembrar em 20 minutos"), saída deve entregar diretamente a um canal sem envolvimento da sessão principal

**Dica:** Agrupar verificações similares periódicas em `HEARTBEAT.md` em vez de criar múltiplos cron jobs. Usar cron para horários precisos e tarefas standalone.

**Coisas para verificar (rotacionar entre estas, 2-4 vezes por dia):**
- **Emails** — Alguma mensagem não lida urgente?
- **Calendário** — Eventos próximos nas próximas 24-48h?
- **Mentions** — Notificações Twitter/social?
- **Weather** — Relevante se o humano pode sair?

**Quando entrar em contato:**
- Email importante chegou
- Evento de calendário chegando (<2h)
- Algo interessante que encontrou
- Passou >8h desde que disse algo

**Quando ficar quieto (HEARTBEAT_OK):**
- Madrugada (23:00-08:00) a menos que urgente
- Humano claramente ocupado
- Nada novo desde última verificação
- Acabou de verificar <30 minutos atrás

**Trabalho proativo que pode fazer sem pedir:**
- Ler e organizar arquivos de memória
- Verificar projetos (git status, etc.)
- Atualizar documentação
- Commit e push de suas próprias mudanças
- **Revisar e atualizar MEMORY.md** (manutenção de memória)

**Memory Maintenance (Durante Heartbeats):**
Periodicamente (a cada poucos dias), usar um heartbeat para:
1. Ler através de arquivos recentes `memory/YYYY-MM-DD.md`
2. Identificar eventos significativos, lições ou insights que valem manter a longo prazo
3. Atualizar `MEMORY.md` com aprendizados destilados
4. Remover informações desatualizadas de MEMORY.md que não são mais relevantes

---

## 9. Referências e Documentação

### 9.1. Documentos Principais

- **FLUXO_AGENTES.md** — Fluxo operacional completo Notion (Presidente, Diretores, Especialistas), regras de deduplicação, templates, esteira Einstein→Tech→Backend
- **AGENTS.md** — Regras e padrões dos agentes, autonomia, resiliência, comportamento group chats, heartbeats, live feedback
- **PLANO_PROJETO.md** — Plano de projeto (logging obrigatório), resiliência operacional
- **TOOLS.md** — Ferramentas e skills disponíveis, scripts Gmail, SmartEnvios MCP
- **NOTION.md** — Workspaces Notion configurados, mapeamento diretor→skill
- **KNOWLEDGE.md** — Conhecimento histórico e padrões
- **SETUP_COMPLETO.md** — Este documento (referência única consolidada)
- **agents/einstein/AGENTS.md** — Regras específicas do Einstein (ferramentas operacionais MCP, escalonamento para Notion, comportamento group chats)

### 9.2. Documentação Técnica

- **docs/development/LOGGING_AND_RULES.md** — Regras técnicas de logging
- **docs/MODEL_FALLBACK_STRATEGY.md** — Estratégia de fallback de modelos
- **scripts/gmail/README.md** — API reference Gmail
- **scripts/gmail/AGENT_WORKFLOW.md** — Workflow para especialistas Mail-Pro/Person
- **scripts/gmail/UNSUBSCRIBE_GUIDE.md** — Guia de unsubscribe de emails promocionais
- **agents/einstein/README.md** — Configuração Einstein
- **agents/einstein/AGENTS.md** — Regras específicas Einstein (MCP, escalonamento, group chats)
- **agents/einstein/ENRICHMENT_GUIDE.md** — Como enriquecer Einstein
- **agents/einstein/SOURCES.md** — Fontes de informação SmartEnvios
- **agents/backend-engineer/README.md** — Configuração Engenheiro Backend
- **agents/backend-engineer/AGENTS.md** — Regras específicas Engenheiro Backend

### 9.3. Templates

- **templates/notion-card-openclaw.md** — Template oficial para cards OpenClaw (propriedades padrão, roteamento recomendado, corpo padrão, comentário padrão do especialista)

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
- [ ] Einstein configurado e testado (gatilho Discord, ferramentas MCP, escalonamento Notion)
- [ ] Engenheiro Backend configurado (esteira Einstein→Tech→Backend)
- [ ] Agente de Governança configurado (cron 10min, escalonamento automático)
- [ ] Agente de Otimização e Performance implementado (cron diário 7h)

### 10.4. Crons

- [ ] Cron Diretor Tech (rotinas Mail-Pro)
- [ ] Cron Diretor Pessoal (rotinas Mail-Person)
- [ ] Cron Governança (health check 10min, ID: `e5bb7978-cd99-4e8d-924a-b4d42a140c1e`)
- [ ] Cron Otimização (diário 7h, ID: `9cb7163f-2e4e-48ed-9035-8148c77c5968`)

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
- **Governança:** verifica saúde a cada 10 minutos
- **Otimização:** analisa logs diariamente

### 11.2. Atualizações

- Documentar mudanças em `memory/YYYY-MM-DD.md`
- Atualizar `SETUP_COMPLETO.md` quando houver mudanças significativas na arquitetura, fluxos ou implementações
- Revisar e atualizar templates quando necessário
- Manter sincronização entre FLUXO_AGENTES.md, AGENTS.md, PLANO_PROJETO.md e SETUP_COMPLETO.md

### 11.3. Evolução Contínua

- **Governança:** garante execução mesmo com erros, escalona automaticamente crons para evitar colisões
- **Otimização:** elimina gargalos identificados pela Governança, mede tendência diária (incidentes hoje vs ontem)
- **Objetivo:** reduzir progressivamente a carga de trabalho da Governança através de otimizações preventivas
- **Fluxos maduros:** devem gerar zero incidentes para a governança

### 11.4. Regras Críticas de Operação

**Regra de escopo e deduplicação (OBRIGATÓRIO):**
- Cada agente opera apenas em dois status: capta do status de entrada e checa duplicidade no status de saída
- Nunca consultar status fora do escopo do agente (ver tabela em secção 6.1)

**Regra de profundidade da descrição (CRÍTICO):**
- Presidente escreve descrição funcional (sem detalhamento técnico)
- Diretor detalha tecnicamente ao mover para Priorizado
- Esta separação é fundamental para o funcionamento do sistema

**Comentários incrementais (OBRIGATÓRIO para especialistas):**
- Especialistas DEVEM postar comentários no card do Notion ao longo da execução, não apenas no final
- Máximo 300 caracteres por comentário
- Mostrar jornada de execução: etapa atual, progresso, o que pretende fazer a seguir

---

**Fim do documento**
