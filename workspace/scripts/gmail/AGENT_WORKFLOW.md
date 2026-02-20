# Agent Workflow - Mail-Pro & Mail-Person

Fluxo completo para especialistas processarem emails com contexto e priorização inteligente.

## 1. Executar Workflow Completo

```bash
./scripts/gmail/workflow.sh pro 20  # Mail-Pro
./scripts/gmail/workflow.sh personal 20  # Mail-Person
```

**Output:** JSON com emails analisados, ordenados por prioridade (score DESC).

**Campos importantes:**
- `summary.needsDraft` - Emails que merecem rascunho (score >= 50)
- `summary.needsReview` - Emails para revisar (score >= 20)
- `summary.needsLabel` - Emails para apenas labelar (score >= 0)
- `summary.shouldIgnore` - Auto-replies e notificações (score < 0)

## 2. Processar Emails por Prioridade

### A. Emails com `action: "draft"` (score >= 50)

**Critérios:**
- Menção direta ao Rafael
- Thread com múltiplas mensagens
- Keywords de urgência (prazo, solicito, ASAP)

**Ação:**
1. Ler thread completa com contexto (`thread.context`)
2. **Criar rascunho contextualizado** baseado no histórico
3. Aplicar label `Mail-{Pro|Person}-Importante`
4. Arquivar

**Exemplo de rascunho contextualizado:**
```
Subject: Re: [assunto original]

Olá [nome extraído do from],

[Referência específica ao contexto da thread]

[Resposta relevante baseada no histórico]

Att,
Rafael
```

### B. Emails com `action: "review"` (score 20-49)

**Critérios:**
- Keywords de ação (dúvida, problema, ajuda)
- De domínio conhecido (smartenvios.com)
- Não é bulk/list mail prioritário

**Ação:**
1. Ler snippet e thread.context
2. **Decidir se merece rascunho** (análise manual do agente)
3. Se sim: criar rascunho contextualizado
4. Aplicar label `Mail-{Pro|Person}-Aguardando`
5. Arquivar

### C. Emails com `action: "label"` (score 0-19)

**Critérios:**
- Não tem urgência clara
- Pode ser notificação de baixo valor
- Bulk/list mail sem keywords críticos

**Ação:**
1. Aplicar label `Mail-{Pro|Person}-BaixoValor`
2. Arquivar
3. **Não criar rascunho**

### D. Emails com `action: "ignore"` (score < 0)

**Critérios:**
- Auto-replies (Out of Office, Delivery Failed)
- Notificações de sistema (noreply@)
- Bulk mail sem relevância

**Ação:**
1. Apenas arquivar
2. **Não labelar**, **não criar rascunho**

## 3. Criar Rascunho Contextualizado

**Estrutura do comando:**
```bash
./scripts/gmail/gmail.sh pro draft-create \
  "destinatario@example.com" \
  "Re: Assunto Original" \
  "Corpo com contexto..." \
  "threadId"
```

**Template de rascunho (use o agente para gerar):**

```
Olá [Nome],

[Referência específica: "Vi que você mencionou X no dia Y..."]

[Resposta relevante baseada no contexto da thread]

[Próximos passos ou call-to-action se necessário]

Att,
Rafael
```

**Importante:**
- **SEMPRE incluir `threadId`** para manter contexto da conversa
- Extrair nome do remetente do campo `from`
- Referenciar pontos específicos da thread (datas, assuntos, decisões)
- Ser objetivo e direto

## 4. Aplicar Labels

**Labels padrão (criar se não existir):**

**Mail-Pro:**
- `Mail-Pro-Importante` (action: draft)
- `Mail-Pro-Aguardando` (action: review)
- `Mail-Pro-BaixoValor` (action: label)

**Mail-Person:**
- `Mail-Person-Importante` (action: draft)
- `Mail-Person-Aguardando` (action: review)
- `Mail-Person-BaixoValor` (action: label)

**Comandos:**
```bash
# Criar label (ou reusar existente)
LABEL_ID=$(./scripts/gmail/gmail.sh pro label-create "Mail-Pro-Importante" | jq -r '.id')

# Aplicar label
./scripts/gmail/gmail.sh pro label-apply "messageId" "$LABEL_ID"
```

## 5. Arquivar

```bash
./scripts/gmail/gmail.sh pro archive "messageId"
```

Remove label `INBOX` mas mantém o email (não deleta).

## 6. Registrar Resultado no Card Notion

**Formato obrigatório do comentário:**

```markdown
## Resultado executivo
- Status: Sucesso | Sucesso parcial | Falha
- Caixa analisada: rafael.pereira@smartenvios.com
- Janela/consulta: is:unread (últimos 20)

## Métricas
- Não lidos encontrados: 20
- Triados: 20
  - Importantes (draft): 2
  - Aguardando (review): 5
  - BaixoValor (label): 10
  - Ignorados (auto-reply): 3
- Labels aplicadas: Mail-Pro-Importante (2), Mail-Pro-Aguardando (5), Mail-Pro-BaixoValor (10)
- Rascunhos criados: 2
- Arquivados: 20

## Evidências (IDs/assuntos)
- [19c796afb11f9001] AWS ElastiCache Update → BaixoValor, arquivado
- [19baea64cb0c3e41] Solicitação Pedido SM8189985192P02 → Aguardando, arquivado
- [19xxxxx] Cliente urgente → Rascunho criado, Importante, arquivado

## Decisões e próximos passos
- Rascunhos criados: 2 emails de clientes diretos aguardando revisão humana
- Pendências: 5 emails em "Aguardando" precisam de acompanhamento manual
- Aprendizados: Emails de infraestrutura AWS podem ir direto para BaixoValor
```

## 7. Exemplo Completo

```bash
#!/bin/bash
# Processar emails Mail-Pro

# 1. Workflow completo
RESULT=$(./scripts/gmail/workflow.sh pro 20)

# 2. Para cada email com action: draft
echo "$RESULT" | jq -r '.processed[] | select(.priority.action == "draft") | .messageId' | while read MSG_ID; do
  # Pegar detalhes
  EMAIL=$(echo "$RESULT" | jq --arg id "$MSG_ID" '.processed[] | select(.messageId == $id)')
  
  THREAD_ID=$(echo "$EMAIL" | jq -r '.threadId')
  SUBJECT=$(echo "$EMAIL" | jq -r '.subject')
  FROM=$(echo "$EMAIL" | jq -r '.from')
  CONTEXT=$(echo "$EMAIL" | jq -r '.thread.context')
  
  # [AGENTE DECIDE: Gerar rascunho contextualizado baseado em CONTEXT]
  
  DRAFT_BODY="Olá,\n\nReferente ao email anterior...\n\nAtt,\nRafael"
  
  # Criar rascunho
  ./scripts/gmail/gmail.sh pro draft-create \
    "$FROM" \
    "Re: $SUBJECT" \
    "$DRAFT_BODY" \
    "$THREAD_ID"
  
  # Label + arquivar
  LABEL_ID=$(./scripts/gmail/gmail.sh pro label-create "Mail-Pro-Importante" | jq -r '.id')
  ./scripts/gmail/gmail.sh pro label-apply "$MSG_ID" "$LABEL_ID"
  ./scripts/gmail/gmail.sh pro archive "$MSG_ID"
done

# 3. Registrar no Notion...
```

## Tips

**Para criar rascunhos contextualizados:**
- Leia `thread.context` (últimas 3 mensagens da conversa)
- Identifique o tema principal e decisões anteriores
- Referencie datas/números/nomes específicos mencionados
- Mantenha tom consistente com thread anterior

**Para decidir se merece rascunho (review):**
- Cliente direto? → Sim
- Pergunta técnica específica? → Sim
- Notificação de status genérico? → Não
- Mensagem interna de sistema? → Não

**Otimizações:**
- Use batch operations: crie labels primeiro, depois aplique em loop
- Cache label IDs para não criar a cada run
- Limite workflow a 50 emails por execução para não estourar rate limit
