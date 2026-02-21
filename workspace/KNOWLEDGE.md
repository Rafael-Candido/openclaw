# KNOWLEDGE.md - Historical Knowledge & Patterns

Este arquivo documenta padrões, descobertas e soluções que funcionaram bem para referência futura.

**⚠️ IMPORTANTE: Este arquivo deve ser atualizado sempre que aprendermos algo novo!**

**Última documentação: 2026-02-20 23:01**

---

## 2026-02-20 – jira-helper.sh (Einstein)

O `agents/einstein/scripts/jira-helper.sh` é o helper para API Jira usado pelo Einstein. Credenciais: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_PROJECT_KEY` no .env. Estado em `agents/einstein/.pi/` (jira-assignees.json, jira-field-cache.json). Comandos: assignee-resolve, assignee-list, sync-fields, create. Ver `agents/einstein/TOOLS.md` e `knowledge/jira/classification-rules.md`.

## 2026-02-21 – Presidente: modelo + notion-helper + descrição (CRÍTICO)

**Problema:** Presidente (DeepSeek) descrevia ações em vez de executá-las; cards criados sem descrição.

**Solução:**
1. **Modelo:** `google/gemini-3-pro-preview` (troca de DeepSeek — melhor uso de tools)
2. **Exec obrigatório:** Presidente usa APENAS `notion-helper.sh` via exec, nunca skill notion
3. **Descrição obrigatória:** `create-card` aceita 8º param `body_file` — Presidente escreve /tmp/pres-desc.txt com markdown (## Contexto, ## Objetivo, ## Escopo, ## Critérios, ## Restrições) e passa ao create-card
4. **Agentes iniciais:** SmartEnvios Agente='Tech' (Diretor Tech pega), Pessoal Agente='Diretor Pessoal' (Diretor Pessoal pega)

## 2026-02-20 – Engenheiro SmartEnvios — Estrutura de personalização

O `eng-smartenvios` passou a ter a mesma estrutura do eng-prompt: BOOTSTRAP, IDENTITY, HEARTBEAT, SOUL, TOOLS, USER. Ambos os engenheiros (prompt e smartenvios) usam essa convenção para personalização do agente.

## 2026-02-20 – Governança — Session roots ampliados

O `governance-check.sh` limpa locks obsoletos em 4 roots: `main/sessions`, `einstein/sessions`, `eng-smartenvios/sessions`, `eng-prompt/sessions`. MAX_LOCK_MIN=5min.

## 2026-02-20 – Einstein — Base de conhecimento consolidada

O `agents/einstein/KNOWLEDGE.md` consolida 5 fontes para dúvidas SmartEnvios:

1. **Notion** — Processos (21f21016...), Base Conhecimento (95c2dfe4...), Transportadoras, FAQ
2. **Zendesk** — https://smartenvios.zendesk.com/hc/pt-br (scraping não funcionou; referenciar URL)
3. **YouTube** — Playlists SmartEnvios (4: Tutorial Geral, Integrações, Funcionalidades Avançadas, Dicas)
4. **GitHub** — 10 microserviços em `/var/www/ms.*` (local-repos.md, local-repos.json)
5. **MCP** — https://staging.smartenvios.tec.br/mcp (CEP, OKRs, Jira, Zendesk)

Inclui fluxos de trabalho e FAQ consolidada. Export Notion: `export_einstein_base.py` → `knowledge/notion/base-conhecimento.md`.

## 2026-02-20 – Einstein — models.json (DeepSeek por agente)

Cada agente pode ter `agent/models.json` com providers específicos. Ex.: `agents/einstein/agent/models.json` define DeepSeek (deepseek-chat, deepseek-reasoner) com `DEEP_API_KEY`. Sobrescreve/configura modelos por agente fora do `openclaw.json` global.

## 2026-02-20 – Comentários progressivos dos especialistas

Especialistas devem postar comentários curtos no card Notion ao longo da execução.

**Formato:** `[HH:MM] emoji Etapa X/N: resumo. Próximo: ação.` (max 300 chars)

**Benefício:** visibilidade da jornada + governança detecta travamento pelo `last_edited_time`.

## 2026-02-20 – Mail-Pro travamento recorrente (padrão conhecido)

**Sintoma:** Card fica em Em andamento por horas; sessão acumula centenas de msgs, rate limit.

**Sugestões documentadas:** (1) aumentar intervalo cron 10min → 15–20min; (2) cleanup automático de sessão após run; (3) throttling workflow.sh (max 20 emails/run); (4) monitorar duração e timeout. Governança força especialista automaticamente quando detecta card abandonado. Card de melhoria criado para Engenheiro de Prompt implementar fix.

---

## 2026-02-20 – notion-helper.sh — Comandos disponíveis

O `workspace/scripts/notion-helper.sh` é o helper principal para interações com Notion via exec (evita JSON complexo em curl). Comandos:

- **query** `<db_id> <api_key_var> <agent> [status1] [status2]` — Lista cards (Tipo=OpenClaw, Agente=X, Status em status1 ou status2)
- **update-status** `<page_id> <api_key_var> <new_status>`
- **comment** `<page_id> <api_key_var> <message> [agente]` — Se agente informado, prefixa "[Agente] " no comentário (assinar sempre)
- **get-page** `<page_id> <api_key_var>`
- **get-blocks** `<page_id> <api_key_var>`
- **append-body** `<page_id> <api_key_var> [file]` — Adiciona blocos ao corpo (## heading, - item, 1. item). Lê de stdin se file omitido
- **create-card** `<db_id> <api_key_var> <title> [status] [tipo] [agente] [criador] [body_file]` — Se body_file (caminho) informado, adiciona descrição ao card (markdown: ## heading, - item)

**API key vars:** `NOTION_SMARTENVIOS_API_KEY`, `NOTION_PERSONAL_API_KEY`, `NOTION_CANPER_API_KEY`

## 2026-02-20 – Scripts notion-canper-* (DB Canper)

Scripts Python para o Notion Canper (DB `14abf9163c9680ff822bc2e32f6bec4b`). Usam `NOTION_CANPER_API_KEY`. Úteis para Diretor de Negócios e fluxos Canper:

- `notion-canper-query.py` — Consulta cards (Aguardando, OpenClaw)
- `notion-canper-schema.py` — Schema do DB
- `notion-canper-status.py` — Status dos cards
- `notion-canper-update-card.py` — Atualiza card
- `notion-canper-add-content.py` — Adiciona conteúdo
- `notion-canper-check-recent.py`, `notion-canper-check-stalled.py`, `notion-canper-robust-check.py` — Checks operacionais

Para agentes: usar `exec` com esses scripts ou `notion-helper.sh` com `NOTION_CANPER_API_KEY`.

## 2026-02-20 – export_einstein_base.py

Script que exporta a base de conhecimento do Notion SmartEnvios (DB `95c2dfe4878a4180a99f4a2c21ac0ea9`) para `workspace/agents/einstein/knowledge/notion/base-conhecimento.md`. Usa `NOTION_SMARTENVIOS_API_KEY`. Existe também `export_einstein_base_v2.py` (variação).

## 2026-02-20 – Engenheiro de Prompt — Estrutura de personalização

O `eng-prompt` tem ficheiros de personalização do agente (nome, vibe, emoji, preferências do utilizador):

- **BOOTSTRAP.md** — Fluxo "Hello World" para primeira configuração (nome, natureza, emoji, USER, SOUL)
- **IDENTITY.md** — Nome, criatura, vibe, emoji
- **USER.md** — Nome do utilizador, como tratar, timezone
- **SOUL.md** — O que importa, como agir, fronteiras
- **TOOLS.md** — Ferramentas do eng-prompt
- **HEARTBEAT.md** — Heartbeat/ritual de manutenção

O BOOTSTRAP deve ser removido após a primeira configuração.

---

## 2026-02-21 – Notion: API key vs skill (CRÍTICO)

**Problema:** O projeto foi construído sem depender do módulo skill notion-personal como comando. O acesso ao Notion é feito via **API key** configurada no `.env` e referenciada em `openclaw.json` skills.entries.

**Como funciona:**
- `skills.entries.notion` → `${NOTION_SMARTENVIOS_API_KEY}` (DB SmartEnvios)
- `skills.entries.notion-personal` → `${NOTION_PERSONAL_API_KEY}` (DB Pessoal)
- `skills.entries.notion-canper` → `${NOTION_CANPER_API_KEY}` (DB Canper)

**Importante:** Agentes que usam skill `notion` recebem o skill genérico; o workspace/contexto pode alterar qual API key é usada. Para o **Engenheiro de Prompt** e scripts que acessam Notion Pessoal:

- **Usar `notion-helper.sh`** com o parâmetro `NOTION_PERSONAL_API_KEY` (nome da variável de ambiente)
- O script lê a chave do `.env` via `source` e usa na chamada à API
- **NÃO** usar `openclaw notion query` — não existe comando notion no CLI
- **NÃO** assumir que skill "notion-personal" existe como comando; é apenas entrada de config

**Regra para novos agentes/crons:** Se precisar acessar Notion Pessoal, usar `exec` com `notion-helper.sh` e `NOTION_PERSONAL_API_KEY`. Para Notion SmartEnvios, skill `notion` ou `notion-helper.sh` com `NOTION_SMARTENVIOS_API_KEY`.

## 2026-02-21 – message.send WhatsApp (target E.164)

**Problema:** Ao enviar alerta via message.send para WhatsApp, o target deve ser **E.164** (número internacional). Usar nome como "Rafael Pereira" causa erro: `Unknown target "Rafael Pereira" for WhatsApp. Hint: <E.164|group JID>`.

**Formato correto:**
- `channel`: `whatsapp`
- `target`: `+5516992793422` (E.164 obrigatório, sem espaços, sem nome)

**Regra:** Na governança e em qualquer cron que envie WhatsApp, sempre usar `target=+5516992793422`. NUNCA usar nome de contato. O número está na allowlist do `openclaw.json` channels.whatsapp.allowFrom.

## 2026-02-21 – Engenheiro de Prompt: executar = implementar

**Problema:** O Engenheiro de Prompt estava analisando cards e escrevendo plano, mas NÃO implementava as mudanças técnicas. Cards ficavam com análise sem execução.

**Regra:** EXECUTAR significa IMPLEMENTAR. Quando o card pede desabilitar cron, alterar intervalo, ajustar script/config: o Engenheiro de Prompt DEVE fazer (openclaw cron disable, edit jobs.json, edit scripts). Análise sem implementação = falha. O comment final deve evidenciar o que FOI FEITO, não o que será feito.

## 2026-02-21 – Escalonamento por cadeia de dependencia + frequencia dinamica

**Problema:** Crons rodavam fora de ordem (especialistas antes de diretores), frequencia fixa desperdicava recursos.

**Solucao:** Grade por cadeia de dependencia (Presidente->Diretores->Especialistas) + frequencia dinamica.

**Ordem por dependencia (offsets desde T0 = 1771653600000):**
- Fase 1 (criar): Governanca +0s (10min fixo) | Presidente +0s (30min dinamico)
- Fase 2 (priorizar): Dir.Negocios +3min | Dir.Tech +3min | Dir.Pessoal +5:30 (35min dinamico)
- Fase 3 (executar): Mail-Pro +10min (15min dinamico) | Mail-Person +12:30 | Eng.Prompt +13:30 (30min fixo) | Otimizador +15min (20min fixo) | Eng.SmartEnvios +20min (30min fixo)

**Frequencia dinamica (governanca ajusta everyMs baseado em volume):**
- Presidente: 30 / 60 / 120 / 180 min
- Diretores: 35 / 65 / 125 / 185 min
- Mail-Pro/Person: 15 / 30 / 60 / 120 min
- Criterio: lastDurationMs >60s = volume alto (tier 0), <10s = ocioso (sobe tier)

**Crons fixos:** Governanca (10min), Eng.Prompt (30min), Eng.SmartEnvios (30min), Otimizador (20min)

**maxConcurrent: 2** em openclaw.json. Governanca NAO reescreve anchorMs (grade fixa). Apenas ajusta everyMs dos crons dinamicos.

## 2026-02-21 – Especialistas Engenheiro SmartEnvios e Engenheiro de Prompt

**Engenheiro SmartEnvios** (id: `eng-smartenvios`):
- Fullstack para todos os repos SmartEnvios em `/var/www/`. Recebe demandas do Diretor Tech (bugs, melhorias, MCP, etc.). GitHub https://github.com/SmartEnvios. Notion SmartEnvios (DB adec12e735dc41a3bb7c274b287f3a10). Skill: `notion`.

**Engenheiro de Prompt** (id: `eng-prompt`):
- Manutenção da estrutura OpenClaw — agentes, prompts, documentação. Reporta ao Diretor Pessoal. Otimizador e Governança criam cards para ele evoluir a estrutura (eficiência, baixo custo, qualidade). Documenta aprendizados, atualiza SETUP_COMPLETO, versiona em GitHub https://github.com/Rafael-Candido. Notion Pessoal (DB bfcbe7a7a3a745489e605e0762af12a9). Skill: `notion-personal`.

Toda vez que descobrirmos um padrão, resolvermos um problema, ou configurarmos algo novo, devemos documentar aqui para referência futura. Este é o conhecimento histórico acumulado que permite replicar soluções e evitar erros já conhecidos.

## 2026-02-21 – Sincronização documentação com openclaw.json

**Alterações:** Documentação alinhada ao estado real do código e da config.

- **SETUP_COMPLETO.md:** Agentes (main, eng-smartenvios, eng-prompt, einstein), modelos e fallbacks, canais Discord (bindings → einstein, dmPolicy allowFrom 932709376790233088), tools do Einstein (allow: read, write, edit, exec, web_search, web_fetch, message, sessions_history; deny: gateway, sessions_*, subagents, cron, process, nodes, browser, canvas), variáveis DEEP_API_KEY e XAI_API_KEY/GROK_API_KEY.
- **TOOLS.md:** Lista de modelos (DeepSeek, xAI/Grok, Gemini 2.5/3), Einstein tools e restrições, nota sobre exec permitido para MCP.
- **agents/einstein/README.md** e **AGENTS.md:** Modelo Grok como primary, ferramentas permitidas/bloqueadas alinhadas a openclaw.json; exec permitido para MCP.

**Referência:** Fonte de verdade para agentes e canais é `openclaw.json`; manter SETUP_COMPLETO, TOOLS e docs do Einstein sincronizados após mudanças de config.

## 2026-02-21 – Guardrails anti-regressão (legado + segredos + drift)

**Problema recorrente:** alterações automáticas voltavam a introduzir path legado, segredo hardcoded e divergência entre prompt-base e mensagem efetiva do cron.

**Causa raiz:**
- Edição parcial (arquivo-base atualizado, mas `cron/jobs.json` sem sync)
- Uso de path absoluto de máquina (`/Users/...`, `/private/...`) em scripts/prompt
- Inclusão de credencial literal em JSON versionado
- Confusão entre arquivo de config versionado x arquivo de estado runtime

**Regra definitiva (obrigatória para qualquer LLM/agente):**
1. **Nunca hardcode de segredo** em arquivo rastreado no git (`apiKey`, `token`, `secret`).
2. **Sempre usar variável de ambiente** (`${...}`) para credenciais/config sensível.
3. **Nunca hardcode de path de máquina** em scripts/prompt; usar:
   - `OPENCLAW_CONFIG_DIR` para config/logs/runtime
   - `PROJECT_ROOT`/`SCRIPT_DIR` para caminhos de repositório
4. **Se atualizar prompt-base, sincronizar cron efetivo**:
   - atualizar `workspace/scripts/optimizer-prompt.txt`
   - atualizar `cron/jobs.json` (payload.message do job correspondente)
   - atualizar backup de jobs se fizer parte do fluxo operacional
5. **Distinguir arquivos de estado runtime** (tokens/sessions/approvals) de arquivos versionados:
   - runtime pode conter dados transitórios locais
   - não usar runtime como template de configuração

**Checklist rápido antes de encerrar tarefa:**
- `rg` por segredos hardcoded (`sk-`, `apiKey: "literal"`, `token: "literal"`).
- `rg` por path legado (`/Users/.../.openclaw`, `/private/var/www/openclaw`).
- Validar JSON alterado (`python3 -m json.tool ...`).
- Rodar lint local (`workspace/scripts/lint.sh`).
- Confirmar que prompt e cron estão sincronizados.

**Sinal de alerta crítico:** se um arquivo "volta sozinho" após edição, existe processo concorrente sobrescrevendo. Pausar e estabilizar ambiente antes de continuar.

## 2026-02-20 – Regra de Resiliência para Automação (atualizada 13:23)

**Princípio fundamental: TENTAR PRIMEIRO, FALHAR DEPOIS, NUNCA ASSUMIR**

### Regras obrigatórias para todos os especialistas

1. **Sempre executar scripts/APIs antes de declarar bloqueio:**
   - NUNCA assumir que credenciais estão vazias sem tentar
   - NUNCA declarar "sem token" sem executar o comando de autenticação
   - Se um script falhou ontem, TENTAR NOVAMENTE hoje (pode ter sido corrigido)

2. **Evidência concreta de erro:**
   - Copiar o output completo do comando que falhou
   - Registrar no card Notion: comando executado + erro retornado
   - Só então declarar bloqueio técnico

3. **Buscar identificadores via API quando necessário:**
   - Ex.: `GET /v1/users` no Notion para achar `Solicitante`
   - Documentar a tentativa concreta quando registrar pendência

4. **Aplicar a todos os agentes:**
   - Main, diretores, especialistas, Einstein

### Caso real: "Bloqueio de e-mail" falso (2026-02-20)

**Problema:** Especialistas Mail-Pro e Mail-Person declararam "sem GMAIL_PROFESSIONAL_REFRESH_TOKEN" em múltiplos runs, movendo cards para Concluído sem execução.

**Causa raiz:** Tokens EXISTIAM no .env e scripts gmail.sh FUNCIONAVAM perfeitamente, mas especialistas assumiram erro sem executar `./gmail.sh <profile> auth`.

**Fix aplicado:** 
- Prompts atualizados: "Só declarar bloqueio de credencial após teste real de Gmail API no run"
- Documentado em KNOWLEDGE.md como padrão obrigatório
- Regra: se script falhou antes, TENTAR DE NOVO (ambiente pode ter sido corrigido)

## 2026-02-20 – Discord Gateway Instável (issue conhecido)

**Sintoma:** Centenas de logs "Attempting resume with backoff" + "connection stalled: no HELLO received within 30000ms" durante horas.

**Causa raiz:** Discord.js não recupera gracefully de timeouts de rede. Issue conhecido da biblioteca discord.js, não há fix fácil no OpenClaw.

**Impacto:** Conexão Discord pode ficar instável por períodos longos (observado: 15h-16h em 2026-02-19), mas geralmente se recupera sozinha.

**Mitigação:**
- Se instabilidade persistir por >2h, considerar restart do gateway: `openclaw gateway restart`
- Monitorar logs em `${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}/logs/gateway.log`
- Se virar padrão diário, escalar para Rafael avaliar se vale trocar de biblioteca Discord

**Status:** Tolerável por enquanto — instabilidade não impede operação principal (WhatsApp, WebChat, Notion, Gmail funcionam independentemente).

---
[Rest of the original content remains unchanged]
---
## Error in Notion Card Update (2026-02-20)
- **Issue:** Attempt to run './scripts/notion/update_card.sh' failed with 'no such file or directory'.
- **Cause:** Script is missing or incorrectly pathed.
- **Fix:** Para crons de especialista (Mail-Pro, Mail-Person etc.): usar **notion-helper.sh** — `workspace/scripts/notion-helper.sh query/update-status/comment`. NÃO usar skill notion (agentes de cron rodam em modo isolated sem skills). O script `update_card.sh` não existe.
- **Context:** Occurred during Mail-Pro specialist task for cron ae4a0347-2e03-46ad-8595-6b9476c45d79.