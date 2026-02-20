# OpenClaw

Sistema de agentes autônomos para gestão de fluxos operacionais através de múltiplos canais.

## Visão Geral

O OpenClaw é um sistema de agentes autônomos que opera através de:
- **Gateway OpenClaw:** gerencia agentes, crons, canais (Discord, WhatsApp, WebChat)
- **Notion:** sistema de cards para fluxo operacional (Aguardando → Priorizado → Em andamento → Concluído)
- **Agentes especializados:** Main (Presidente), Diretores (3), Especialistas (Mail-Pro, Mail-Person), Einstein, Governança, Otimização

## Estrutura

- `workspace/` - Código fonte e documentação dos agentes
- `openclaw.json` - Configuração do gateway
- `.env` - Variáveis de ambiente (não versionado)

## Documentação

Consulte `workspace/SETUP_COMPLETO.md` para documentação completa do sistema.

## Licença

Proprietário - Rafael Candido
