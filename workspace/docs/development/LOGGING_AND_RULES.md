# LOGGING_AND_RULES.md – Referência técnica de logging

Este documento é a referência técnica para o plano em [PLANO_PROJETO.md](../../PLANO_PROJETO.md).

**Se o código vive noutro repositório,** copie este ficheiro para esse repo em `docs/development/LOGGING_AND_RULES.md` ou mantenha um link único (URL ou path) como fonte de verdade.

**Âmbitos de logging:** O plano distingue (1) **operacional** — configuração do gateway, rotação, ficheiros — documentado em KNOWLEDGE.md; (2) **em código** — subsystem, logInfo/logError, requestId, redacção — documentado aqui e em PLANO_PROJETO.md. Não confundir: alterações em `openclaw.json` ou paths de log são operacionais; alterações em handlers, canais e skills seguem as regras deste documento.

---

## Regras expandidas com exemplos

### 1. createSubsystemLogger(subsystem) vs logInfo/logWarn/logError/logDebug

- **Módulos com domínio claro** (ex.: gateway WS, canal WhatsApp, skill Notion): usar `createSubsystemLogger(subsystem)` para que os logs tenham o subsistema no metadata.
- **Demais casos:** usar `logInfo`, `logWarn`, `logError`, `logDebug` de `src/logger.ts`.

Exemplo de mensagem estruturada:
```ts
logger.info({ subsystem: 'gateway/ws', requestId, durationMs: Date.now() - start }, 'connect ok');
```

### 2. Nunca console.log em produção

- Proibido em código de produção. Usar o logger central; em desenvolvimento/debug pode-se usar o logger com nível debug.

### 3. Início e fim de operações com durationMs

- No início da operação: `const start = Date.now();` (ou equivalente).
- No fim (sucesso ou falha): incluir `durationMs: Date.now() - start` no log.

Exemplo:
```ts
const start = Date.now();
// ... operação ...
logInfo({ operation: 'sync', durationMs: Date.now() - start }, 'sync completed');
```

### 4. Erros em nível ERROR com requestId e errorCode

- Todo erro que afecte a request ou operação deve ser logado em ERROR com:
  - `requestId` (ou `operationId`) para correlacionar
  - `errorCode` (string estável para métricas/alertas)

Exemplo:
```ts
logError({ requestId, errorCode: 'AUTH_FAILED', err }, 'authentication failed');
```

### 5. Decisões de roteamento e seleção de agente

- Logar quando o sistema escolhe um agente, um canal ou uma rota (ex.: "agent selected: main", "channel: whatsapp"). Evitar logar dados sensíveis (tokens, PII).

### 6. Dados que nunca devem aparecer em log

**Lista explícita:**
- Tokens (API, auth, session, gateway)
- Senhas
- E-mails completos (usar máscara: `***@domain.com` se necessário)
- Números de telefone completos (últimos 4 dígitos apenas se necessário para suporte)
- IDs de documento PII (CPF, etc.)
- Trechos de corpo de mensagens ou documentos que possam ser confidenciais

**Padrões de redacção:**
- Máscara: `***@domain.com`, `****1234`
- Sufixo: `REDACTED`
- Hash: quando for preciso correlacionar sem expor (ex.: `hash: sha256(secret).slice(0,8)`)

**Exemplo de helper (pseudo):**
```ts
function redactForLog(obj: Record<string, unknown>): Record<string, unknown> {
  const out = { ...obj };
  if (out.token) out.token = '[REDACTED]';
  if (out.password) out.password = '[REDACTED]';
  if (out.email && typeof out.email === 'string') out.email = out.email.replace(/^.+@/, '***@');
  return out;
}
logInfo(redactForLog(params), 'request');
```

---

## Verificação e enforcement

### Checklist de code review (PR)

- [ ] Nenhum `console.log` em código de produção (apenas logger).
- [ ] Operações significativas com log de início/fim e `durationMs`.
- [ ] Erros logados em ERROR com `requestId` e `errorCode`.
- [ ] Decisões de roteamento/agente logadas.
- [ ] Nenhum token, senha ou PII em mensagens de log; dados sensíveis redactados.

### Lint

- Sugestão: regra ESLint que marca `console.log` como erro (ou aviso) em paths de produção, com exceções documentadas para `scripts/` ou build-only.

### CI (opcional)

- Script que faz `grep -r "console\.log" src/` (ou equivalent) e falha o build se encontrar, com exceções em ficheiros listados (ex.: `scripts/dev-*.ts`).
- No workspace atual, usar `scripts/check-logging.sh` como verificação mínima local (retorna exit code 1 se encontrar `console.log` em paths de produção).

---

## Código legado e migração

- As regras aplicam-se em prioridade a **código novo** e a **alterações em ficheiros existentes**: ao tocar num ficheiro, deixar o logging alinhado com as regras.
- **Migração em fases sugerida:** (1) gateway e RPC/WS; (2) canais (whatsapp, web, etc.); (3) agentes e skills; (4) utilitários e infra.
- Não exigir refactor em massa de uma vez; aceitar melhoria incremental quando o ficheiro for modificado por outro motivo.
