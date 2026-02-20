# Einstein - Especialista SmartEnvios

Agente isolado para responder dúvidas sobre a plataforma SmartEnvios em canais Discord.

## Configuração

- **Agente ID:** `einstein`
- **Discord Mention:** `@1439351480514646087`
- **Workspace:** `/var/www/openclaw/workspace/agents/einstein`
- **Modelo (openclaw.json):** `xai/grok-4-1-fast-non-reasoning` (primary), fallbacks Grok 3 Mini, Grok 3, DeepSeek, GPT-4 Turbo, Claude Sonnet/Opus, Grok Beta

## Restrições

**Ferramentas bloqueadas:** `gateway`, `sessions_send`/`sessions_spawn`/`sessions_list`, `subagents`, `cron`, `process`, `nodes`, `browser`, `canvas`

**Ferramentas permitidas:** `read`, `write`, `edit`, `web_search`, `web_fetch`, `message`, `exec`, `sessions_history`, skill `notion`

- **exec:** permitido para MCP SmartEnvios (`scripts/smartenvios-mcp.sh`) e consultas necessárias ao suporte
- Sem acesso a infraestrutura interna (gateway, crons, subagents, browser, canvas)

## Enriquecimento

Para adicionar conhecimento ao Einstein:

1. **Documentação técnica:**
   ```bash
   # Adicionar docs da API
   cp /path/to/api-docs.md agents/einstein/KNOWLEDGE.md
   ```

2. **Exemplos de código:**
   ```bash
   mkdir -p agents/einstein/examples
   # Adicionar snippets de integrações
   ```

3. **FAQs:**
   - Editar `agents/einstein/KNOWLEDGE.md` com perguntas/respostas comuns

## Teste

Para testar o Einstein:
1. Mencione `@1439351480514646087` em um canal Discord configurado
2. Faça uma pergunta sobre SmartEnvios
3. Verifique se ele responde sem acesso a informações internas

## Logs

Ver atividade do Einstein:
```bash
tail -f /var/www/openclaw/logs/gateway.log | grep einstein
```
