# Einstein - Especialista SmartEnvios

Agente isolado para responder dúvidas sobre a plataforma SmartEnvios em canais Discord.

## Configuração

- **Agente ID:** `einstein`
- **Discord Mention:** `@1439351480514646087`
- **Workspace:** `/var/www/openclaw/workspace/agents/einstein`
- **Modelo:** Herda fallback do default (Claude Sonnet 4.5 + backups)

## Restrições

**Ferramentas bloqueadas:**
- `exec` (sem execução de comandos)
- `gateway` (sem acesso a config)
- `sessions_*` (sem controle de outros agentes)
- `subagents` (não spawna sub-agentes)
- `cron` (não cria/modifica cron jobs)

**Ferramentas permitidas:**
- `read` (documentação do workspace)
- `web_search` (buscar informações públicas)
- `web_fetch` (consultar docs externas)
- `message` (responder no Discord)

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
