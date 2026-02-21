# KNOWLEDGE.md - Base de Conhecimento SmartEnvios (Consolidada)

> **Última consolidação:** 2026-02-20 21:37:01

## 📋 Sumário Executivo

Esta base integra múltiplas fontes de informação para responder dúvidas sobre a plataforma SmartEnvios:

1. **Notion** - Processos internos e base de conhecimento
2. **Zendesk** - Artigos públicos de suporte
3. **YouTube** - Playlists de tutoriais
4. **GitHub** - Repositórios de microserviços
5. **MCP** - API para automações

---

## 📚 Fontes de Informação

### 1. Notion SmartEnvios

**Workspace principal:** Processos internos e documentação

**Bancos de dados principais:**
- **Processos** (`21f21016bd48807588b1f3e0e13f72c3`): Árvore completa de rotinas por área
- **Base de Conhecimento** (`95c2dfe4878a4180a99f4a2c21ac0ea9`): FAQ interna (246 entradas)
- **Transportadoras Parceiras** (`2ac5a2553557458e947f891bb639c4a0`): SLAs e requisitos
- **F.A.Q** (`1f64d30b-d485-4221-8f9c-709a50aada86`): Categorias de artigos

**Como acessar:**
- API Notion com chave `NOTION_SMARTENVIOS_API_KEY`
- Scripts: `notion-export.sh`, `notion_export_recursive.py`
- Exportar para: `agents/einstein/knowledge/notion/`

### 2. Zendesk Público

**URL:** https://smartenvios.zendesk.com/hc/pt-br

**Conteúdo:** Artigos oficiais de suporte para clientes

**Status atual:** Scraping automático não funcionou (possível bloqueio)
**Alternativa:** Referenciar URL diretamente ou usar busca manual

### 3. YouTube - Playlists Oficiais

**Canal:** SmartEnvios (tutoriais e guias)

**Playlists disponíveis (4):**
1. **Tutorial Geral** - Introdução e primeiros passos
2. **Integrações** - Conexão com e-commerces e APIs
3. **Funcionalidades Avançadas** - Recursos complexos
4. **Dicas e Melhores Práticas** - Otimização e eficiência

**Arquivo local:** `agents/einstein/knowledge/youtube/playlists.md`

### 4. GitHub - Repositórios Locais

**Localização:** `/var/www/ms.*` (10 microserviços)

**Inventário completo:** `agents/einstein/knowledge/github/local-repos.md`

**Microserviços principais:**
- `ms.atendimento` - Sistema de atendimento
- `ms.connectors` - Conectores e integrações
- `ms.crm` - CRM interno
- `ms.customer-service` - Serviço ao cliente
- `ms.expedition-hub` - Hub de expedição
- `ms.label-processor` - Processador de etiquetas
- `ms.notifications` - Sistema de notificações
- `ms.points` - Sistema de pontos
- `ms.ticket-generator` - Gerador de tickets
- `ms.zardbank` - Integração financeira

**Tecnologias predominantes:** Node.js, TypeScript, NestJS, Docker

### 5. MCP SmartEnvios

**URL staging:** https://staging.smartenvios.tec.br/mcp

**Funcionalidades:**
- Consulta de CEP
- Criação/atualização de OKRs
- Integração com Jira
- Automação de tickets Zendesk

**Script:** `scripts/smartenvios-mcp.sh`

---

## 🔄 Fluxos de Trabalho Recomendados

### Para dúvidas gerais de usuários:
1. Verificar Base Einstein (Notion) por pergunta similar
2. Buscar em Zendesk por artigos relacionados
3. Recomendar playlist YouTube apropriada
4. Se não encontrar, pesquisar em Processos Notion

### Para dúvidas técnicas/bugs:
1. Identificar microserviço relacionado no GitHub
2. Verificar README e documentação do repositório
3. Consultar logs ou configurações típicas
4. Sugerir troubleshooting baseado em código

### Para integrações:
1. Playlist YouTube "Integrações"
2. Código fonte em `ms.connectors`
3. Artigos Zendesk de setup
4. Testar via MCP se aplicável

---

## ❓ FAQ Consolidada - Perguntas Mais Frequentes

### Integração com Shopify
**Resposta:** Sim, através do app oficial na Shopify App Store.

**Links:**
- App: https://apps.shopify.com/smartenvios
- Playlist: Integrações (vídeo específico)
- Microserviço: `ms.connectors`

### Como rastrear um envio?
**Resposta:** Painel SmartEnvios → aba "Envios" ou link de rastreamento enviado.

**Microserviço:** `ms.expedition-hub`

### Webhooks não funcionam
**Troubleshooting:**
1. Verificar URL configurada
2. Testar com curl
3. Checar logs em `ms.notifications`
4. Validar HTTPS

### CEP inválido
**Causa:** Formato incorreto ou não encontrado.

**Solução:**
1. Validar formato: `XXXXX-XXX`
2. Consultar Correios
3. Microserviço: `ms.connectors`

---

## 📁 Estrutura de Diretórios do Einstein

```
agents/einstein/knowledge/
├── notion/
│   ├── base-conhecimento.md      # Base Einstein (FAQ)
│   ├── processos.md              # Processos SmartEnvios
│   └── transportadoras.md        # Parceiros logísticos
├── youtube/
│   └── playlists.md              # 4 playlists oficiais
├── github/
│   ├── local-repos.md            # Inventário ms.*
│   └── local-repos.json          # JSON com detalhes
├── zendesk/
│   ├── artigos.md                # Lista de artigos
│   └── indice.md                 # Índice resumido
├── jira/
│   └── classification-rules.md   # Regras de classificação
└── mcp/
    └── (documentação MCP)
```

---

## 🛠️ Scripts de Apoio

**Localização:** `/var/www/openclaw/workspace/scripts/`

| Script | Função | Uso |
|--------|--------|-----|
| `notion-export.sh` | Exportar página Notion | `./notion-export.sh <pageId> <output>` |
| `notion_export_recursive.py` | Exportar recursivo | `python3 notion_export_recursive.py <pageId> <output>` |
| `notion-helper.sh` | Helper para API | Consultar AGENTS.md |
| `smartenvios-mcp.sh` | Cliente MCP | `./smartenvios-mcp.sh login/call/tools` |
| `inventory_github_repos.py` | Inventário GitHub | `python3 inventory_github_repos.py` |
| `update_youtube_playlists.py` | Atualizar playlists | `python3 update_youtube_playlists.py` |
| `export_einstein_base.py` | Exportar Base Einstein | `python3 export_einstein_base.py` |
| `simple_zendesk_scrape.py` | Scraping Zendesk | `python3 simple_zendesk_scrape.py` |

---

## 📝 Template de Resposta (Best Practice)

```markdown
✅ [Resposta direta e afirmativa]

📋 [Explicação detalhada em 2-3 frases]

🔗 **Links úteis:**
- [Título do recurso](URL)
- [Outro recurso](URL)

🛠️ **Se precisar de ajuda técnica:**
- Microserviço relacionado: `ms.nome-do-servico`
- Script para testar: `nome-do-script.sh`
```

---

## 📊 Status Atual da Base

| Fonte | Status | Última Atualização | Notas |
|-------|--------|-------------------|-------|
| Notion Processos | ⚠️ Parcial | 2026-02-20 | Exportação manual necessária |
| Base Einstein | ⚠️ Parcial | 2026-02-20 | 246 entradas, schema a verificar |
| YouTube Playlists | ✅ Completo | 2026-02-21 | 4 playlists detalhadas |
| GitHub Repos | ✅ Completo | 2026-02-21 | 10 microserviços inventariados |
| Zendesk | ⚠️ Limitado | 2026-02-21 | Scraping bloqueado, URLs apenas |
| MCP | ✅ Configurado | 2026-02-20 | Script funcionando |

---

## 🎯 Próximos Passos Recomendados

1. **Exportar Processos Notion** recursivamente para markdown
2. **Resolver schema Base Einstein** para extrair perguntas/respostas
3. **Implementar scraping Zendesk** alternativo (API ou manual)
4. **Atualizar FAQ** com novas perguntas frequentes
5. **Integrar MCP** em respostas automáticas quando aplicável
6. **Monitorar atualizações** nos repositórios GitHub

---

*Documentação mantida pelo Engenheiro de Prompt - Varredura automática*
