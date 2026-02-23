# Gmail Skill - Mail-Pro & Mail-Person

Scripts para triagem, gerenciamento de labels, rascunhos e arquivamento de emails via Gmail API.

## Arquivos

- **gmail.sh** - API wrapper de baixo nível (auth, list, get, get-full, thread, labels, draft-create, archive)
- **triage.sh** - Triagem de não lidos com metadata estruturada
- **export-sent-samples.py** - Exporta e-mails enviados (pro + personal) para JSON (para extração de estilo)
- **extract-communication-patterns.py** - Lê o JSON exportado e gera padrões por contexto (cliente, time, etc.)
- **README.md** - Este arquivo

## Setup

**Credenciais já configuradas em `/var/www/openclaw/.env`:**
- `GMAIL_PROFESSIONAL_*` (Mail-Pro: rafael.pereira@smartenvios.com)
- `GMAIL_PERSONAL_*` (Mail-Person: rafael.silva.pereira10@gmail.com)

## Uso

### 1. Listar não lidos

```bash
./triage.sh pro 20    # Mail-Pro: pega 20 não lidos com metadata
./triage.sh personal 10  # Mail-Person: pega 10 não lidos
```

**Output:**
```json
{
  "profile": "pro",
  "unread": 3,
  "messages": [
    {
      "id": "19c796afb11f9001",
      "threadId": "19c796afb11f9001",
      "subject": "AWS Update...",
      "from": "AWS <health@aws.com>",
      "date": "Fri, 20 Feb 2026 04:59:38 +0000",
      "snippet": "...",
      "labels": ["UNREAD", "INBOX"]
    }
  ]
}
```

### 2. Ler thread completa (com histórico)

```bash
./gmail.sh pro thread "19c796afb11f9001"
```

**Output:** JSON com todos os emails da conversa (histórico completo).

### 3. Gerenciar labels

**Listar labels existentes:**
```bash
./gmail.sh pro labels | jq '.labels[] | {id, name}'
```

**Criar label (ou reusar existente):**
```bash
./gmail.sh pro label-create "Mail-Pro-Importante"
# Output: {"id": "Label_123", "name": "Mail-Pro-Importante", "existed": false}
```

**Aplicar label:**
```bash
./gmail.sh pro label-apply "19c796afb11f9001" "Label_123"
```

### 4. Criar rascunho

**Rascunho simples:**
```bash
./gmail.sh pro draft-create \
  "destinatario@example.com" \
  "Assunto do email" \
  "Corpo do email com múltiplas linhas"
```

**Rascunho em thread existente (reply):**
```bash
./gmail.sh pro draft-create \
  "destinatario@example.com" \
  "Re: Assunto original" \
  "Corpo da resposta" \
  "19c796afb11f9001"  # threadId
```

**Regra anti-ruído (obrigatória):**
- não criar rascunho automático para e-mails promocionais/outreach;
- só gerar `draft` quando o e-mail estiver claramente direcionado ao usuário (destinatário direto) **e** houver sinal de pedido/ação;
- casos sem pedido explícito devem cair para `review` ou `label`.

### 5. Arquivar email

```bash
./gmail.sh pro archive "19c796afb11f9001"
```

Remove label `INBOX` → email arquivado mas não deletado.

## Workflow Completo (Exemplo)

```bash
#!/bin/bash
# Triagem Mail-Pro

# 1. Pegar não lidos
UNREAD=$(./triage.sh pro 20)
echo "$UNREAD" | jq .

# 2. Para cada não lido importante, criar rascunho
MSG_ID="19c796afb11f9001"
THREAD_ID="19c796afb11f9001"

./gmail.sh pro draft-create \
  "cliente@example.com" \
  "Re: Sua solicitação" \
  "Olá, segue resposta..." \
  "$THREAD_ID"

# 3. Aplicar label
LABEL_ID=$(./gmail.sh pro label-create "Mail-Pro-Importante" | jq -r '.id')
./gmail.sh pro label-apply "$MSG_ID" "$LABEL_ID"

# 4. Arquivar
./gmail.sh pro archive "$MSG_ID"
```

## Integração com Agente

**Uso recomendado via exec:**

```javascript
// Listar não lidos
const result = await exec({
  command: "/var/www/openclaw/workspace/scripts/gmail/triage.sh pro 20"
});
const data = JSON.parse(result.stdout);

// Decisão do agente: classificar cada email
for (const msg of data.messages) {
  // Lógica de classificação...
  
  // Se importante:
  await exec({
    command: `./gmail.sh pro draft-create "${msg.from}" "Re: ${msg.subject}" "Rascunho..." "${msg.threadId}"`
  });
  
  // Aplicar label + arquivar
  const labelId = "Label_123";
  await exec({
    command: `./gmail.sh pro label-apply "${msg.id}" "${labelId}"`
  });
  await exec({
    command: `./gmail.sh pro archive "${msg.id}"`
  });
}
```

## Labels Padrão

**Mail-Pro (SmartEnvios):**
- `Mail-Pro-Importante`
- `Mail-Pro-Aguardando`
- `Mail-Pro-BaixoValor`

**Mail-Person:**
- `Mail-Person-Importante`
- `Mail-Person-Aguardando`
- `Mail-Person-BaixoValor`

## Troubleshooting

**Token expirado:**
```bash
rm /tmp/gmail-token-pro.cache
./gmail.sh pro auth  # Force refresh
```

**Erro de autenticação:**
```bash
# Verificar se refresh tokens estão configurados
grep GMAIL_.*_REFRESH_TOKEN /var/www/openclaw/.env | sed 's/=.*/=***/'
```

**Debug:**
```bash
# Testar auth
./gmail.sh pro auth

# Listar labels
./gmail.sh pro labels | jq .

# Pegar um email específico
./gmail.sh pro get "MESSAGE_ID" | jq .
```

### Exportar e-mails enviados e extrair padrões de comunicação

Para alimentar o **rafael-dna** (ou prompts de rascunho) com exemplos reais de como tu respondes:

1. **Exportar enviados** (requer .env com credenciais Gmail carregado):
   ```bash
   cd /var/www/openclaw && . .env 2>/dev/null; python3 workspace/scripts/gmail/export-sent-samples.py --max 20
   ```
   Gera `workspace/docs/email-samples-sent.json` (pro + personal, até 20 por perfil).

2. **Extrair padrões por contexto** (cliente, time, suporte, etc.):
   ```bash
   python3 workspace/scripts/gmail/extract-communication-patterns.py workspace/docs/email-samples-sent.json --out workspace/docs/communication-patterns-from-samples.md
   ```
   Gera `communication-patterns-from-samples.md` com secções por contexto e notas de estilo (resposta curta, próximo passo explícito, saudação informal, etc.). Podes revisar e incorporar trechos em `workspace/docs/rafael-dna.md` ou usar o .md nos prompts de draft.

## Performance

- **Token cache:** 50min (renovado automaticamente)
- **Rate limits:** Gmail API ~250 quota/user/second (não deve ser problema para triagem)
- **Batch operations:** Use loops com sleep se processar >100 emails

## Segurança

- Tokens armazenados em `/tmp/gmail-token-*.cache` (expiram em 1h)
- Refresh tokens em `/var/www/openclaw/.env` (nunca commitar!)
- Scripts executam como usuário `rafaelcanper`
