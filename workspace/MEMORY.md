# MEMORY.md - Long-Term Memory

Curated long-term context for `main`.

## User Context
- User: Rafael Pereira.
- Preferred language: Portuguese.
- Core environment path: `/var/www/openclaw`.
- Timezone: America/Sao_Paulo (GMT-3).
- Discord user ID: 932709376790233088
- Empresas: SmartEnvios (tech/logística), Canper (negócios).

## Arquitetura de Agentes (consolidado 2026-02-20)

### Hierarquia operacional
- **Presidente** (main): cria cards em Aguardando com descrição funcional
- **3 Diretores** (Tech, Pessoal, Negócios): captam Aguardando, priorizam com descrição técnica
- **Especialistas** (Mail-Pro, Mail-Person, Engenheiro Backend): executam de Priorizado até Concluído
- **Einstein**: agente operacional no Discord (suporte + MCP + Jira + histórico canais)
- **Governança**: health check a cada 10min, escalonamento automático, recuperação de travamentos
- **Otimizador**: análise diária às 7h, elimina causas raiz dos problemas

### Propriedades padrão de cards Notion
- Status: Aguardando → Priorizado → Em andamento → Concluído
- Tipo: OpenClaw
- Solicitante: Rafael Pereira
- Agente: conforme responsável

### Deduplicação — chave dupla
- Assunto + Agente no status de SAÍDA do agente
- Presidente checa Aguardando, Diretor checa Priorizado, Especialista checa Em andamento

## Lições críticas aprendidas

### Rate limit por concorrência
- Nunca rodar muitos crons ao mesmo tempo — escalonar com gap mínimo de 2min
- maxConcurrent=2 é suficiente para o volume atual
- Governança redistribui anchors automaticamente se detectar colisão

### Profile "minimal" do OpenClaw
- NÃO registra tools como binding real — agente vê nas instruções mas escreve como texto
- Solução: remover profile para usar padrão do sistema

### Sandbox "all" bloqueia tudo
- Impede acesso a .env, sessões de outros agentes, filesystem fora do workspace
- Para agentes que precisam de acesso amplo (Einstein): sandbox mode "off"

### SOUL.md é lei
- O agente obedece SOUL.md ao pé da letra — se diz "não executa comandos", ele não executa mesmo tendo a ferramenta
- Sempre alinhar SOUL.md com as ferramentas reais do agente

### Crons systemEvent no main = poluição
- Lembretes repetitivos inundam o chat e queimam tokens
- Usar crons isolated com agentTurn em vez de systemEvent no main

### APIs disponíveis no .env
- Discord: `DISCORD_BOT_TOKEN`
- Jira: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_PROJECT_KEY=SME`
- SmartEnvios MCP: `SMARTENVIOS_MCP_URL`, `SMARTENVIOS_MCP_EMAIL`, `SMARTENVIOS_MCP_PASSWORD`
- Gmail: `GMAIL_*_CLIENT_ID`, `GMAIL_*_CLIENT_SECRET`, `GMAIL_*_REFRESH_TOKEN`
- Notion: 3 workspaces (SmartEnvios, Personal, Canper)
- Modelos: OpenAI, Anthropic, Gemini, Grok

## Recovery Note (2026-02-20)
- The original `agent:main:main` session history was partially lost after model test runs rewired the session pointer.
- Best available reconstruction source is `memory/2026-02-20.md`.
- Preserve this file and keep daily memory files updated before major maintenance.
