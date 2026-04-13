

## Problema: Falha na Criação de Cards Notion com Conteúdo Extenso (HTTP 0)
- **Data:** 2026-04-06
- **Contexto:** Ao tentar criar ou atualizar cards no Notion via `notion-helper.sh create-card` ou `append-body` com um `body_file` contendo conteúdo extenso, a operação falhou consistentemente com erro `HTTP 0` (falha de conexão/requisição `curl`). No entanto, a criação de cards mais simples ou para outros agentes (sem `body_file` complexo) funcionou.
- **Causa Raiz Provável:** Embora o `BODY` JSON pareça bem-formado, o erro `HTTP 0` em `curl` durante o `POST` para `api.notion.com` indica que o payload JSON gerado a partir de um `body_file` muito longo ou complexo pode estar excedendo limites internos da API do Notion ou de conectividade no momento da requisição. Isso não é um erro de validação JSON, mas uma falha de baixo nível na comunicação HTTP/S.
- **Correção Aplicada:** Para contornar, reduziu-se o tamanho e a complexidade do `body_file` utilizado na criação do card de investigação. A delegação de tarefas de investigação que geram logs extensos agora será feita com um contexto mais conciso no card, e a análise de detalhes será feita sob demanda pelo agente especialista.
- **Padrão Reforçado:** Evitar `body_file` excessivamente longos ou complexos (`> 2000-3000 caracteres` como regra de bolso) ao criar ou anexar conteúdo a cards do Notion. Mantenha os corpos dos cards concisos e priorize links para contexto externo ou crie subtarefas para detalhes.
- **Impacto:** Bloqueia a criação e atualização de cards com documentação detalhada inline, exigindo uma abordagem mais modular de documentação e delegação.

## Problema: Discord desconectado por horas sem recuperação automática (2026-04-10)
- **Data:** 2026-04-10
- **Sintoma:** Einstein (Lucas Martins APP) parou de responder no Discord por ~4 horas. Mensagens do time (Edson, Rodrigo) ficaram sem resposta.
- **Causa raiz:** Gateway perdeu conexão WebSocket com Discord (DNS timeout, `ENOTFOUND discord.com`, `stale-socket`). O auto-restart interno do gateway esgotou 10 tentativas. O health checker da governança (`discord-gateway-health.sh`) não detectou o problema porque: (1) a janela de logs é de 20 min — erros antigos saem da janela; (2) sem erros na janela e sem `runtime_connected: false` explícito, o checker reportava `stable`.
- **Correção aplicada (3 partes):**
  1. **`discord-gateway-health.sh`:** Novo caso `login-stale-no-runtime` — se o último login tem mais de `max(login_stale_min * 3, 60)` minutos e o runtime não está conectado, marca `issue: true`. Também usa `runtimeLastConnectedAt` como fallback quando o log não tem a linha de login.
  2. **`governance-check.sh` (`recover_on_discord_gateway_outage`):** Cooldown reduzido (1/3, mínimo 5 min) para `login-stale-no-runtime`. Verificação pós-restart (3 tentativas × 10s) para confirmar reconexão. Contador `consecutiveRecoveries` no state file. Alerta WhatsApp direto quando login > 60 min ou 3+ restarts consecutivos sem sucesso.
  3. **Restart manual do gateway** restabeleceu a conexão imediatamente (DNS já estava acessível).
- **Padrão:** Quando o gateway perde conexão e esgota auto-restart, a governança (cron 5 min) agora detecta e tenta restart com verificação. Se falhar repetidamente, alerta no WhatsApp.
- **Risco residual:** Se a rede do host estiver completamente fora, o restart não resolve. O alerta WhatsApp depende de o WhatsApp estar funcional.

