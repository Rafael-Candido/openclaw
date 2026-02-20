# Model Fallback Strategy

**Última atualização:** 2026-02-20 01:11 GMT-3

## Contexto

Configuração de fallback inteligente para rotação automática de modelos em caso de rate limit, falhas de API, ou indisponibilidade temporária.

## Ordem de Prioridade (11 modelos)

OpenClaw tenta os modelos nesta sequência quando o primary falha:

1. **anthropic/claude-sonnet-4-5** (PRIMARY)  
   - Tier: Standard  
   - Uso: Geral, equilibrado custo/capacidade

2. **anthropic/claude-3.7-sonnet**  
   - Tier: Standard  
   - Backup imediato, mesmo provider

3. **anthropic/claude-3.5-sonnet**  
   - Tier: Standard  
   - Segundo backup Anthropic

4. **google/gemini-1.5-pro**  
   - Tier: Standard  
   - Alternativa Google, capacidade similar

5. **openai/gpt-5.1-codex**  
   - Tier: Premium  
   - Modelo potente para tarefas complexas

6. **anthropic/claude-opus-4-6**  
   - Tier: Premium  
   - Máxima capacidade Anthropic (custo alto)

7. **google/gemini-1.5-flash**  
   - Tier: Fast  
   - Google rápido, econômico

8. **openai/gpt-4-turbo**  
   - Tier: Standard  
   - OpenAI intermediário

9. **anthropic/claude-3-haiku**  
   - Tier: Fast  
   - Anthropic econômico, tarefas simples

10. **xai/grok-beta**  
    - Tier: Experimental  
    - X.AI, fallback experimental

11. **openai/gpt-4**  
    - Tier: Standard  
    - OpenAI clássico

12. **anthropic/claude-3-opus**  
    - Tier: Premium  
    - Último recurso Anthropic premium

## Estratégia de Rotação

- **Automático:** OpenClaw detecta falha e tenta próximo fallback
- **Sem cooldown explícito:** Depende de retry interno do provider
- **Logs transparentes:** Rotações aparecem no log do gateway (`/var/www/openclaw/logs/gateway.log`)

## Tiers Explicados

### Standard (Equilibrado)
Modelos com boa relação custo/capacidade. Uso geral.  
- Claude Sonnet 4.5, 3.7, 3.5  
- Gemini 1.5 Pro  
- GPT-4 Turbo, GPT-4

### Premium (Máxima Capacidade)
Modelos mais caros, reservados para tarefas complexas ou quando standard falha.  
- Claude Opus 4.6, Claude 3 Opus  
- GPT-5.1 Codex

### Fast (Econômico)
Modelos rápidos/baratos para tarefas simples ou quando outros estão indisponíveis.  
- Claude 3 Haiku  
- Gemini 1.5 Flash

### Experimental
Modelos novos ou em beta, últimos recursos.  
- Grok Beta

## Rate Limit Handling

1. **Detecção automática:** OpenClaw identifica erro 429 (rate limit) ou 503 (overload)
2. **Rotação imediata:** Passa para próximo fallback na lista
3. **Retry com backoff:** Alguns providers aplicam exponential backoff interno

## Monitoramento

Para ver qual modelo está sendo usado:
```bash
tail -f /var/www/openclaw/logs/gateway.log | grep -i "model"
```

Para checar rotações/fallbacks:
```bash
tail -f /var/www/openclaw/logs/gateway.log | grep -i "fallback\|rate limit\|retry"
```

## Ajustes Futuros

Se um modelo específico estiver consistentemente falhando ou com rate limit:
1. Reordene a lista em `agents.defaults.model.fallbacks`
2. Remova modelos problemáticos temporariamente
3. Adicione novos modelos conforme disponibilidade

**Comando para editar config:**
```bash
openclaw config edit
# ou use gateway tool: gateway(action=config.patch, ...)
```

## Notas

- **Custo:** Rotação automática pode escalar custos se cair para tiers premium frequentemente. Monitorar uso via logs.
- **Latência:** Fallback adiciona delay (1-3s) para retry/conexão com novo provider.
- **Contexto:** Alguns modelos têm limites de context window diferentes — pode haver truncamento.

---

**Referências:**
- Config: `~/.openclaw/openclaw.json`
- Logs: `/var/www/openclaw/logs/gateway.log`
- Schema: `gateway(action=config.schema)`
