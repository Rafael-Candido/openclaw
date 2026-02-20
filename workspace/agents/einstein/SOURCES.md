# Fontes de Conhecimento SmartEnvios

Einstein tem acesso a múltiplas fontes de informação sobre a SmartEnvios.

## 🗂️ Notion SmartEnvios

**Acesso:** Via `NOTION_SMARTENVIOS_API_KEY` (configurado no `.env`)

**Páginas principais:**
- **Processos:** https://www.notion.so/21f21016bd48807588b1f3e0e13f72c3
- **Base de Conhecimento:** https://www.notion.so/95c2dfe4878a4180a99f4a2c21ac0ea9

**Como usar:**
```bash
# Exportar página para markdown
./scripts/notion-export.sh "PAGE_ID" "output.md"

# Buscar no Notion via API
curl -X POST "https://api.notion.com/v1/search" \
  -H "Authorization: Bearer $NOTION_SMARTENVIOS_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -d '{"query": "texto a buscar"}'
```

---

## 📚 Zendesk Help Center (Público)

**URL:** https://smartenvios.zendesk.com/hc/pt-br

**Conteúdo:**
- Artigos de ajuda
- FAQs
- Guias de uso
- Troubleshooting

**Como usar:**
```bash
# Buscar artigos (público, sem auth)
curl -s "https://smartenvios.zendesk.com/hc/api/v2/help_center/pt-br/articles.json?per_page=100"

# Buscar por query
curl -s "https://smartenvios.zendesk.com/hc/api/v2/help_center/articles/search.json?query=rastreio"
```

**Sugestão:** Criar cache local dos artigos mais acessados.

---

## 🎥 YouTube Playlists

### 1. Tutorial Geral
**URL:** https://www.youtube.com/playlist?list=PLCGSdWtokK2yEF-TwdQy-hSLUWE6Z262K
**Primeiro vídeo:** https://www.youtube.com/watch?v=mSOers8WJos

### 2. Integrações
**URL:** https://www.youtube.com/playlist?list=PLCGSdWtokK2xQgVnf0wpWCFVCePMWOI38
**Primeiro vídeo:** https://www.youtube.com/watch?v=uc1hYNlvU58

### 3. Funcionalidades Avançadas
**URL:** https://www.youtube.com/playlist?list=PLCGSdWtokK2ymXUfIfHEEpHTNJ_m9KfAv
**Primeiro vídeo:** https://www.youtube.com/watch?v=6J4w0d3DV_Y

### 4. Casos de Uso
**URL:** https://www.youtube.com/playlist?list=PLCGSdWtokK2xEFiLG2F2vdTSHlChx11v0
**Primeiro vídeo:** https://www.youtube.com/watch?v=-o4XrTpj7xg

**Como usar:**
- Einstein pode linkar vídeos relevantes em respostas
- Formato de resposta: "Veja este tutorial: [título] - https://youtu.be/VIDEO_ID"

**Sugestão:** Criar índice manual com timestamp de tópicos importantes.

---

## 🔧 MCP (Model Context Protocol)

**URL Staging:** https://staging.smartenvios.tec.br/mcp

**O que é:**
- Interface de context protocol para SmartEnvios
- Pode expor dados estruturados sobre pedidos, rastreios, etc.

**Como usar:**
```bash
# Verificar endpoints disponíveis
curl -s "https://staging.smartenvios.tec.br/mcp" | jq .

# Consultar dados (se auth não necessário)
curl -s "https://staging.smartenvios.tec.br/mcp/endpoint"
```

**⚠️ Nota:** Verificar se precisa de autenticação ou API key.

---

## 💻 GitHub Repos (rafaelcanper)

**Conta:** rafaelcanper (configurada no OpenClaw)

**Como listar repos:**
```bash
gh repo list rafaelcanper --limit 100 --json name,url,description
```

**Repos locais em `/var/www`:**
```bash
ls -la /var/www/
# Cada repo pode ter .env com configs úteis
```

**Como usar:**
- Buscar código-fonte para troubleshooting técnico
- Ver .env de exemplo para configurações
- Consultar README.md para documentação

**Sugestão:** Criar índice de repos com breve descrição.

---

## 🛠️ Como Einstein Deve Usar

### Para dúvidas gerais de uso:
1. **Primeiro:** Zendesk (artigos públicos)
2. **Segundo:** YouTube playlists (vídeos tutoriais)
3. **Terceiro:** Notion (processos internos)

### Para dúvidas técnicas/bugs:
1. **Primeiro:** GitHub repos (código-fonte)
2. **Segundo:** MCP staging (dados em tempo real)
3. **Terceiro:** Notion (documentação técnica)

### Para integrações:
1. **Primeiro:** YouTube playlist "Integrações"
2. **Segundo:** GitHub (exemplos de código)
3. **Terceiro:** Zendesk (guias de integração)

---

## 📝 Próximos Passos

**Para enriquecer ainda mais o Einstein:**

1. **Zendesk:**
   - [ ] Scrape todos os artigos públicos
   - [ ] Criar cache local em `knowledge/zendesk/`
   - [ ] Indexar por categoria/tópico

2. **YouTube:**
   - [ ] Criar índice com timestamps
   - [ ] Transcrever vídeos importantes (YouTube API)
   - [ ] Extrair FAQs dos comentários

3. **GitHub:**
   - [ ] Listar todos os repos rafaelcanper
   - [ ] Indexar READMEs e docs/
   - [ ] Mapear .env de exemplo

4. **MCP:**
   - [ ] Documentar endpoints disponíveis
   - [ ] Criar exemplos de queries
   - [ ] Testar autenticação

5. **Notion:**
   - [ ] Exportar todas as páginas relevantes
   - [ ] Criar busca full-text local
   - [ ] Sincronizar periodicamente

---

## 🔐 Credenciais

**Configuradas no `.env`:**
- `NOTION_SMARTENVIOS_API_KEY` ✅
- `GITHUB_TOKEN` (via `gh auth`) ✅

**Pendentes:**
- MCP staging auth (se necessário)
- Zendesk API token (se quiser usar API privada)
