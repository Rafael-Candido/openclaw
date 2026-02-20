# Auto-Unsubscribe Guide

Scripts para detectar e processar automaticamente unsubscribe de emails promocionais/sociais de baixo valor.

## Scripts

- **`unsubscribe.sh`** - Detecta e executa unsubscribe para um email específico
- **`cleanup-promotions.sh`** - Processa batch de emails promocionais/sociais

## Como Funciona

### 1. Detecção de Emails Promocionais

**Critérios:**
- Gmail category: `CATEGORY_PROMOTIONS` ou `CATEGORY_SOCIAL`
- Sender patterns: `noreply@`, `newsletter@`, `marketing@`, `promo@`, `offers@`

### 2. Extração de Unsubscribe

**Método 1: Header `List-Unsubscribe`**
```
List-Unsubscribe: <https://example.com/unsubscribe?id=123>, <mailto:unsub@example.com>
```

**Método 2: Parsing do corpo do email** (não implementado ainda)

### 3. Execução de Unsubscribe

**URL (automático):**
- Faz requisição GET ao link de unsubscribe
- Verifica HTTP status (200/301/302 = sucesso)
- Arquiva o email após unsubscribe

**Email (manual):**
- Cria rascunho de email para `mailto:unsub@example.com`
- Requer revisão manual antes de enviar

## Uso

### Testar detecção (dry-run)

```bash
# Detectar se email pode ser unsubscribed
./scripts/gmail/unsubscribe.sh personal "messageId" true

# Output:
{
  "messageId": "19c76e20a224da23",
  "subject": "Newsletter...",
  "from": "news@example.com",
  "isPromotional": "true",
  "canUnsubscribe": "true",
  "unsubscribeMethod": "url",
  "unsubscribeUrl": "https://example.com/unsub?id=123"
}
```

### Executar unsubscribe real

```bash
# Unsubscribe de um email específico
./scripts/gmail/unsubscribe.sh personal "messageId" false

# Vai visitar o URL de unsubscribe e arquivar o email
```

### Cleanup automático (batch)

```bash
# Dry-run: apenas detectar
./scripts/gmail/cleanup-promotions.sh personal 20 true

# Executar: unsubscribe e arquivar
./scripts/gmail/cleanup-promotions.sh personal 20 false

# Output:
{
  "profile": "personal",
  "processed": 20,
  "unsubscribed": 15,
  "failed": 5,
  "dryRun": false,
  "details": [...]
}
```

## Integração com Especialistas

### Adicionar ao workflow Mail-Person

**1. Após triagem normal, executar cleanup:**
```bash
# Processar emails normais
./scripts/gmail/workflow.sh personal 100

# Cleanup promocionais com unsubscribe
CLEANUP=$(./scripts/gmail/cleanup-promotions.sh personal 50 false)
echo "$CLEANUP" | jq '{unsubscribed: .unsubscribed, failed: .failed}'
```

**2. Registrar no comentário Notion:**
```markdown
## Métricas
- Promocionais processados: 20
- Unsubscribe executados: 15
- Unsubscribe falhados: 5
```

## Segurança e Boas Práticas

### ⚠️ Cuidados

1. **Validar sender antes de unsubscribe:**
   - Não unsubscribe de emails importantes (confirmações de compra, etc)
   - Verificar se é realmente promocional

2. **Rate limiting:**
   - Não processar mais de 50 emails por run
   - Aguardar 1-2s entre requisições de unsubscribe

3. **Logs:**
   - Sempre registrar quais emails foram unsubscribed
   - Manter histórico para auditoria

### ✅ Indicadores de Segurança

**Pode unsubscribe:**
- Category: PROMOTIONS ou SOCIAL
- From: noreply@, newsletter@, marketing@
- Subject: "Newsletter", "Ofertas", "Promoção"
- List-Unsubscribe header presente

**NÃO unsubscribe:**
- Emails pessoais (de pessoas reais)
- Notificações de serviços críticos (bancos, saúde)
- Confirmações de pedidos/compras
- Emails com menção direta ao usuário

## Automatização via Cron

**Adicionar job semanal de cleanup:**

```javascript
cron.add({
  name: "Cleanup promocionais - unsubscribe automático",
  schedule: { kind: "cron", expr: "0 3 * * 0", tz: "America/Sao_Paulo" }, // Domingo 3am
  sessionTarget: "isolated",
  payload: {
    kind: "agentTurn",
    message: "Executar cleanup de emails promocionais/sociais com unsubscribe automático. Usar /var/www/openclaw/workspace/scripts/gmail/cleanup-promotions.sh para ambos os profiles (pro e personal). Processar até 50 emails por profile. Registrar resultado: quantos foram unsubscribed, quantos falharam. Não unsubscribe de emails importantes ou com menção direta ao usuário."
  }
})
```

## Troubleshooting

**Unsubscribe não funciona (HTTP error):**
- Alguns sites bloqueiam requisições automatizadas
- Solução: criar rascunho manual para revisão

**False positives (unsubscribe de emails importantes):**
- Ajustar filtros em `unsubscribe.sh`
- Adicionar whitelist de senders importantes

**Rate limit do Gmail:**
- Reduzir batch size (50 → 20)
- Aumentar delay entre requisições

## Métricas Esperadas

**Mail-Person (pessoal):**
- ~30-50 emails promocionais por semana
- Taxa de sucesso: ~80-90%

**Mail-Pro (profissional):**
- ~10-20 emails promocionais por semana (menos comum)
- Taxa de sucesso: ~70-80%

## Roadmap

**Futuras melhorias:**
- [ ] Parsing de links no corpo do email (quando header não disponível)
- [ ] Machine learning para detectar newsletters vs emails importantes
- [ ] Whitelist/blacklist configurável por usuário
- [ ] Dashboard de estatísticas (quantos unsubscribed, economia de tempo)
