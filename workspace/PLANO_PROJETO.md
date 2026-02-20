---
description: "Mandatory logging for all code paths — no silent flows allowed"
alwaysApply: true
---

# Plano de Projeto – Logging Obrigatório

## Princípio

**Logging obrigatório em todos os fluxos — nenhum fluxo silencioso permitido.**

Every request, operation, error, and routing decision must be logged.

## Dois âmbitos de logging

- **Operacional:** Configuração do gateway (`openclaw.json`: `logging.level`, `logging.file`), rotação de logs, onde estão os ficheiros. Documentado em [KNOWLEDGE.md](KNOWLEDGE.md).
- **Em código (este plano):** O que cada módulo deve logar (subsystem, logInfo/logError, requestId, redacção). Documentado em PLANO_PROJETO.md e [docs/development/LOGGING_AND_RULES.md](docs/development/LOGGING_AND_RULES.md).

## Regras (checklist)

- Usar `createSubsystemLogger(subsystem)` em módulos com domínio claro.
- Usar `logInfo` / `logWarn` / `logError` / `logDebug` de `src/logger.ts` nos demais casos.
- Nunca usar `console.log` em código de produção.
- Registrar início e fim de toda operação significativa (com `durationMs`).
- Registrar todos os erros em nível ERROR com `requestId` e `errorCode`.
- Registrar todas as decisões de roteamento e seleção de agente.
- Nunca registrar tokens, senhas, PII ou documentos sensíveis.
- Redactar dados sensíveis antes de logar.

**Referência técnica:** [docs/development/LOGGING_AND_RULES.md](docs/development/LOGGING_AND_RULES.md)

## Escopo e onde aplicar

Esta política aplica-se ao código que consome este workspace (ex.: gateway OpenClaw, agentes, skills). Se o código vive noutro repositório, o repositório de código deve ter cópia ou link para as regras (por exemplo `docs/development/LOGGING_AND_RULES.md` no repo do código).

Antes de implementar ou revisar código que toque em fluxos, handlers RPC, canais, skills ou tratamento de erros, ler PLANO_PROJETO.md e LOGGING_AND_RULES.md e aplicar as regras acima.

## Como verificar cumprimento

Ver secção **Verificação e enforcement** em [docs/development/LOGGING_AND_RULES.md](docs/development/LOGGING_AND_RULES.md) (checklist de PR, sugestões de lint e CI).

## Código legado

Para código já existente, ver secção **Código legado e migração** em [docs/development/LOGGING_AND_RULES.md](docs/development/LOGGING_AND_RULES.md). Regras aplicam-se em prioridade a código novo e a alterações em ficheiros existentes; melhoria incremental quando o ficheiro for modificado.

## Autonomia dos agentes

Os agentes devem identificar os próprios erros, corrigir a rota (sem pedir autorização para mudanças não destrutivas) e documentar as lições para não repetir. A referência operativa está em [AGENTS.md](AGENTS.md), subsecção **Autonomia – erros, correção e documentação**.

### Resiliência Operacional (novo)
- Toda automação precisa buscar caminhos alternativos antes de registrar bloqueio (ex.: consultar lista de usuários via API antes de alegar que o dropdown não mostra o solicitante).
- Ao manipular Notion, sempre que um campo `people`/`relation` falhar no preenchimento direto, consultar `/v1/users` ou `/v1/search` para capturar o ID correto e tentar novamente.
- Documentar em comentário/log o ID utilizado e o método adotado (dropdown, lookup via API, etc.).
- Somente após esgotar as rotas previstas registrar pendência no card.
