# Atualizações do OpenClaw (GitHub público) relevantes para este ecossistema

**Repositório:** https://github.com/openclaw/openclaw  
**Versão instalada aqui:** 2026.2.22-2 *(atualizado em 2026-02-23)*  
**Última release pública:** v2026.2.22 (2026-02-23)

---

## Adaptações feitas neste ecossistema (compatibilidade pós-upgrade)

- **Governança (`governance-check.sh`):** Em todos os sítios que leem o estado do cron (saúde operacional, painel WhatsApp, alertas de timeout, heurística de frequência), passámos a usar **`lastRunStatus` com fallback para `lastStatus`**. Assim funciona com gateway 2026.2.22+ (que expõe `lastRunStatus` = execução e `lastDeliveryStatus` = entrega) e continua a funcionar com versões antigas que só têm `lastStatus`.
- **Nada removido:** O fallback para `cron/jobs.json` quando o gateway não responde ao `cron list` mantém-se — com o upgrade o gateway tende a responder melhor durante runs longos, mas o fallback continua a ser a rede de segurança. As variáveis `GOV_USE_SAFE_RUN_FALLBACK`, `GOV_MAIL_CHAIN_FORCE_COOLDOWN_SEC`, etc. também se mantêm; o upstream não as substitui, apenas melhora timeout e lock.

### O que podes fazer depois do upgrade (opcional)

- **Separar “erro de execução” de “erro de entrega”:** Se quiseres que a governança reporte “anúncio não entregue” sem marcar saúde operacional como CRÍTICO, podes usar `lastDeliveryStatus` no relatório (e manter CRÍTICO só para `lastRunStatus` = error). Por agora não alterámos essa lógica.
- **Paralelismo de crons:** No `openclaw.json` (ou config do gateway) podes definir `cron.maxConcurrentRuns` (ex.: 2) se quiseres que até N jobs corram em paralelo; por defeito o upstream passa a respeitar esse valor. O nosso ecossistema hoje não define este campo.

---

## Por que atualizar

Entre 2026.2.17 e 2026.2.22 há dezenas de mudanças que afectam **crons**, **gateway**, **timeouts** e **estabilidade** — alinhadas ao que estás a fazer (governança, 20 rodadas, fluxo estável).

---

## Melhorias que ajudam directamente

### Crons
- **Status vs entrega:** Separação de `lastRunStatus` (execução) e `lastDeliveryStatus` (entrega). Falhas de entrega (ex.: anúncio não enviado) deixam de ser confundidas com falha de execução do cron.
- **Paralelismo:** Respeito por `cron.maxConcurrentRuns` — jobs podem correr em paralelo até ao limite configurado, em vez de sempre em série.
- **Timeout em runs manuais:** O mesmo timeout por job aplica-se a `cron.run` manual e a runs pelo timer; runs forçados não ficam presos indefinidamente.
- **Lock e overlap:** Persistência de `runningAtMs` antes de libertar o lock, evitando que o timer arranque o mesmo job em sobreposição.
- **Cron list/status durante runs:** Execução de `cron.run` manual fora do lock do cron, para `cron.list` e `cron.status` continuarem responsivos durante runs longos.
- **Watchdog do timer:** O scheduler mantém um timer de recheck enquanto `onTimer` corre, para não parar de fazer polling se um tick ficar preso.
- **Sessões isoladas:** Sessões com `sessionTarget=isolated` passam a ter IDs de sessão novos por run, sem reutilizar contexto anterior.
- **Agenda após restart:** Para jobs `every`, preferir `lastRunAtMs + everyMs` quando ainda no futuro após restarts, para o NEXT reflectir a cadência real.
- **Auth em crons isolados:** Propagação da resolução de auth-profile para sessões de cron isoladas (reduz 401 com providers via auth-profiles).
- **Cron delivery:** Anúncios só-texto com thread/topic passam a ser entregues por caminho directo, para destinos forum/thread não caírem.

### Gateway e lock
- **Lock “already running”:** O liveness do lock usa acessibilidade da porta do gateway; reduz falsos “already running” após saídas incorrectas.
- **Restart:** Ajustes em restart-loop e reaquisição do lock em fallbacks de restart in-process.

### Exec e background
- **Background sessions:** O timeout por defeito de exec já não se aplica a sessões em background (`background: true` ou `yieldMs`), para jobs longos não serem cortados no limite padrão.

### Segurança e CLI
- **`openclaw config get`:** Valores sensíveis passam a ser redactados no output, evitando fugas para terminal/histórico.
- **Pairing/scope:** Correções para operadores locais e scope-upgrade não entrarem em loops de “pairing required”.

### Outros úteis
- **Update em dry-run:** `openclaw update --dry-run` para ver canal/tag/restart sem alterar config nem reiniciar.
- **Auto-updater (opcional):** Config `update.auto.*` para actualizações automáticas de pacote (desligado por defeito).
- **Memory/FTS:** Filtros de stop-words para espanhol, português, japonês, coreano e árabe em modo FTS — melhor recall em conversação nessas línguas.
- **Mistral:** Suporte ao provider Mistral (incl. memory embeddings e voz).
- **Synology Chat:** Novo canal nativo Synology Chat.

---

## Como actualizar

```bash
npm install -g openclaw@latest
# ou
pnpm add -g openclaw@latest
```

Depois, reiniciar o gateway (e, se usares daemon, `openclaw gateway install` ou reinício do serviço). Para ver o que mudaria sem aplicar:

```bash
openclaw update --dry-run
```

---

## Referências

- [Release v2026.2.22](https://github.com/openclaw/openclaw/releases/tag/v2026.2.22)
- [Changelog no repo](https://github.com/openclaw/openclaw/blob/main/CHANGELOG.md)
- [Docs oficiais – Updating](https://docs.openclaw.ai/install/updating)
