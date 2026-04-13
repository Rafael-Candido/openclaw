# Agente Business-News - Documentação

## Visão Geral

Agente especializado em buscar e enviar atualizações do mundo dos negócios via WhatsApp todas as manhãs (7h30).

## Estrutura

```
workspace/agents/business-news/
└── AGENTS.md              # Definição do agente e regras

workspace/scripts/
└── business-news-simple.sh               # Versão oficial em uso
```

## Cron Job

- **ID:** `4a784051-745d-4d5e-ae22-161044ec8a34`
- **Nome:** "Business-News - briefing matinal 7h30"
- **Horário:** 7h30 todos os dias (America/Sao_Paulo)
- **Modelo:** xai/grok-3-mini
- **Script:** `business-news-simple.sh`

## Fluxo de Execução

1. **7h30 diariamente** → Cron dispara agente isolado
2. **Agente executa** `business-news-simple.sh`
3. **Script retorna JSON** com mensagem formatada
4. **Agente envia para WhatsApp** (+5516992793422)
5. **Resposta consolidada** (4 linhas max) no canal principal

## Formato da Mensagem WhatsApp

```
📰 BUSINESS BRIEF — [DATA]

*Economia*
- [Título] (Fonte)
  → [Contexto/impacto]

*Tecnologia*
- [Título] (Fonte)
  → [Contexto/impacto]

*Startups*
- [Título] (Fonte)
  → [Contexto/impacto]

*Dica do dia*
[Insight rápido ou tendência]
```

## Evolução Planejada

### Fase 1 (Atual)
- Script determinístico simples
- Formato consistente
- Entrega confiável via WhatsApp

### Fase 2 (Próxima)
- Integração com `web_search` para notícias reais
- Filtros por relevância e qualidade
- Personalização baseada em interesses

### Fase 3 (Futuro)
- Análise de sentimento de mercado
- Alertas de oportunidades/riscos
- Resumos semanais mais detalhados

## Monitoramento

- Verificar `cron list` para status do job
- Logs em `openclaw tasks` (quando houver execução)
- Feedback via WhatsApp do Rafael

## Troubleshooting

### Problema: Mensagem não chega
1. Verificar status do WhatsApp gateway
2. Checar logs do cron job
3. Testar script manualmente: `./scripts/business-news-simple.sh`

### Problema: Formato incorreto
1. Validar JSON do script
2. Verificar escape de caracteres (\n para quebras)
3. Testar envio manual com `message` tool

### Problema: Cron não executa
1. Verificar se job está enabled
2. Checar timezone (America/Sao_Paulo)
3. Testar execução manual: `cron run <jobId>`

## Customização

Para ajustar o conteúdo:
1. Editar `business-news-simple.sh` (mensagem template)
2. Evoluir a lógica com `web_search` + filtros no mesmo agente
3. Manter formato WhatsApp-friendly

Para ajustar horário:
```bash
openclaw cron update <jobId> --schedule.expr "45 8 * * *"
```

## Integração com Outros Agentes

- **Diretor Negócios:** papel canônico de supervisão estrutural
- **Otimizador:** Pode ajustar frequência/custo
- **Engenheiro de Prompt:** Pode melhorar formatação

---

**Última atualização:** 13/04/2026
**Próxima execução:** 07:30 (amanhã)
**Status:** ✅ Registrado no runtime e ativo por cron
