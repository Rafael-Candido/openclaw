# TOOLS.md - Available Tools & Skills

This document lists all available tools, skills, and integrations configured in this workspace.

## Notion Skills

You have access to **3 Notion workspaces** configured as separate skills:

### 1. `notion` (SmartEnvios - Default)
- **Workspace**: SmartEnvios
- **API Key**: Configured via `${NOTION_SMARTENVIOS_API_KEY}`
- **Database ID**: `adec12e735dc41a3bb7c274b287f3a10`
- **Usage**: Default Notion skill, use `notion` commands

### 2. `notion-personal` (Personal)
- **Workspace**: Personal
- **API Key**: Configured via `${NOTION_PERSONAL_API_KEY}`
- **Database ID**: `bfcbe7a7a3a745489e605e0762af12a9`
- **Usage**: Use `notion-personal` commands for personal workspace

### 3. `notion-canper` (Canper)
- **Workspace**: Canper
- **API Key**: Configured via `${NOTION_CANPER_API_KEY}`
- **Database ID**: `14abf9163c9680ff822bc2e32f6bec4b`
- **Usage**: Use `notion-canper` commands for Canper workspace

## Especialistas do fluxo Notion (Agente no card)

Dois especialistas executam a rotina de cards Priorizado → Em andamento → Concluído:

- **Mail-Pro:** Capta cards em Priorizado onde **Agente** = Mail-Pro, lê a descrição, executa, regista resultado no card, report no Discord/WhatsApp, move para Concluído. Uso: tarefas de e-mail profissional (SmartEnvios).
- **Mail-Person:** Capta cards em Priorizado onde **Agente** = Mail-Person, lê a descrição, executa, regista resultado no card, report no Discord/WhatsApp, move para Concluído. Uso: tarefas de e-mail pessoal.

Fluxo completo e template de descrição: [FLUXO_AGENTES.md](FLUXO_AGENTES.md).

## Gmail Skill

Scripts para triagem e gerenciamento de emails via Gmail API.

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

**Operações manuais:**
```bash
# Criar rascunho contextualizado (SEMPRE com threadId!)
./scripts/gmail/gmail.sh pro draft-create "to@example.com" "Re: Subject" "Body com contexto..." "threadId"

# Aplicar label
LABEL_ID=$(./scripts/gmail/gmail.sh pro label-create "Mail-Pro-Importante" | jq -r '.id')
./scripts/gmail/gmail.sh pro label-apply "messageId" "$LABEL_ID"

# Arquivar
./scripts/gmail/gmail.sh pro archive "messageId"
```

**Documentação completa:**
- `scripts/gmail/README.md` - API reference
- `scripts/gmail/AGENT_WORKFLOW.md` - Workflow para especialistas Mail-Pro/Person

## SmartEnvios MCP (API-first)

Cliente local para usar o MCP SmartEnvios com login automático por `.env` e reuso de `session_token`.

- Script: `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh`
- Credenciais no `.env`:
  - `SMARTENVIOS_MCP_URL`
  - `SMARTENVIOS_MCP_EMAIL`
  - `SMARTENVIOS_MCP_PASSWORD`
- Estado local:
  - `workspace/.state/smartenvios_mcp_session_token`

Uso:

```bash
./scripts/smartenvios-mcp.sh login
./scripts/smartenvios-mcp.sh tools
./scripts/smartenvios-mcp.sh call cep_lookup '{"cep":"14020510"}'
```

## Other Skills

- **nano-banana-pro**: Gemini AI integration (uses `${GEMINI_API_KEY}`)
- **sag**: SAG API integration (uses `${SAG_API_KEY}`)

## Available Models

You have access to multiple AI models:
- **OpenAI**: gpt-5.1-codex (primary), gpt-4-turbo, gpt-4, gpt-3.5-turbo
- **Anthropic**: claude-3.7-sonnet, claude-3.5-sonnet, claude-3-opus, claude-3-sonnet, claude-3-haiku
- **Google/Gemini**: gemini-1.5-pro, gemini-1.5-flash, gemini-pro, gemini-ultra
- **X.AI/Grok**: grok-beta, grok-2

All API keys are configured via environment variables in `.env`.

## Specialized Agents

### Einstein (SmartEnvios Support)
- **Agent ID:** `einstein`
- **Workspace:** `/var/www/openclaw/workspace/agents/einstein`
- **Purpose:** Responder dúvidas sobre SmartEnvios
- **Channels:** **100% Discord** (todas as mensagens, canais, DMs)
- **Main channels:** WhatsApp + WebChat (não Discord)
- **Restrictions:** Sem acesso a infraestrutura interna (exec, gateway, sessions)
- **Tools:** read, web_search, web_fetch, message
- **Enrichment:** Ver `agents/einstein/ENRICHMENT_GUIDE.md`

**Como enriquecer o Einstein:**
1. Adicionar FAQs em `agents/einstein/KNOWLEDGE.md`
2. Adicionar exemplos de código em `agents/einstein/examples/`
3. Documentar APIs em `agents/einstein/API_REFERENCE.md`

## Important Notes

- When asked about Notion access, refer to this file or `NOTION.md`
- You can use any of the 3 Notion skills by specifying the skill ID
- Database IDs are available in the `.env` file if needed for specific operations
- Einstein agent is isolated and restricted — only enriches knowledge, does not access internal systems
