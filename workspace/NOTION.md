# Notion Workspaces Configurados

**Última documentação: 2026-02-21 19:44**

Você tem acesso a **3 workspaces do Notion** configurados como skills separadas:

## 1. Notion Personal
- **Skill ID**: `notion-personal`
- **API Key**: `${NOTION_PERSONAL_API_KEY}`
- **Database ID**: `bfcbe7a7a3a745489e605e0762af12a9` (disponível no `.env`)
- **Status**: ✅ **Ativo**

## 2. Notion SmartEnvios
- **Skill ID**: `notion`
- **API Key**: `${NOTION_SMARTENVIOS_API_KEY}`
- **Database ID**: `adec12e735dc41a3bb7c274b287f3a10` (disponível no `.env`)
- **Status**: ✅ **Ativo** (padrão)

## 3. Notion Canper
- **Skill ID**: `notion-canper`
- **API Key**: `${NOTION_CANPER_API_KEY}`
- **Database ID**: `14abf9163c9680ff822bc2e32f6bec4b` (disponível no `.env`)
- **Status**: ✅ **Ativo**

## Como Usar

Cada workspace está disponível como uma skill separada. Você pode:

1. **Usar a skill padrão** (`notion`) para acessar SmartEnvios
2. **Especificar qual workspace usar** mencionando o skill ID:
   - `notion-personal` para Personal
   - `notion-canper` para Canper
   - `notion` para SmartEnvios (padrão)

## Comandos Disponíveis

Todas as skills suportam:
- Ler páginas e databases
- Criar/atualizar entradas em databases
- Buscar informações com filtros
- Adicionar blocos a páginas
- Consultar schemas de databases

**Nota**: Os Database IDs estão disponíveis no arquivo `.env` e podem ser especificados nos comandos quando necessário.

### Acesso via exec (notion-helper.sh)

Para agentes que usam `exec` em vez de skill notion, usar `workspace/scripts/notion-helper.sh` com as variáveis de API key: `query`, `update-status`, `comment`, `get-page`, `get-blocks`, `append-body`, `create-card`. Ver [KNOWLEDGE.md](KNOWLEDGE.md) para detalhes dos comandos.

**Wrapper:** `workspace/scripts/notion/update_card.sh <PAGE_ID> <STATUS> [COMMENT]` — chama notion-helper com retry; usa NOTION_SMARTENVIOS_API_KEY e assinatura "Mail-Pro System".

### Scripts Notion Canper

Scripts Python em `workspace/scripts/notion-canper-*.py` para o DB Canper: query, schema, status, update-card, add-content, check-recent, check-stalled, robust-check. Usar com `NOTION_CANPER_API_KEY`.

## Fluxo Presidente → Diretores → Especialistas

Para o fluxo de trabalho com cards (Aguardando, Priorizado, Em andamento, Concluído) e como cada diretor usa o seu Notion (Tech SmartEnvios, Pessoal, Negócios), ver [FLUXO_AGENTES.md](FLUXO_AGENTES.md).

## Próximos Passos

Após configurar agentes responsáveis, cada agente poderá ser atribuído a um workspace específico do Notion.

Para o fluxo operacional **Presidente → Diretores → Especialistas** (incluindo status dos cards, uso de skills por diretor e gatilho de dúvidas SmartEnvios), veja **FLUXO_AGENTES.md**.

## Mapeamento de pessoas (pendência operacional)

- Campos `Responsável` e `Solicitante` dependem de o utilizador estar visível/compartilhado para a integração.
- Enquanto o utilizador não aparecer na listagem da API, usar `Gestor` (multi-select) como fallback operacional e registrar a pendência no card.
- Próxima ação: confirmar o usuário exato de **Rafael Pereira** dentro do workspace para preenchimento automático via API.
