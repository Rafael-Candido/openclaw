# KNOWLEDGE.md - Base de Conhecimento SmartEnvios

## 📚 Fontes de Informação

Einstein tem acesso a múltiplas fontes. **Consulte SOURCES.md** para detalhes completos.

### Quick Reference

**Para dúvidas gerais:**
1. Zendesk (artigos públicos)
2. YouTube playlists (tutoriais visuais)
3. Notion SmartEnvios (processos internos)

**Para dúvidas técnicas/bugs:**
1. GitHub repos locais (`/var/www/ms.*`)
2. MCP staging
3. Notion (documentação técnica)

**Para integrações:**
1. YouTube → Playlist "Integrações"
2. GitHub → Ver código de conectores
3. Zendesk → Guias de setup

### Fontes Prioritárias (detalhe rápido)
- **Notion / Processos** (`21f21016bd48...`): árvore completa de rotinas por área (Marketing, Comercial, Sucesso do Cliente, Tecnologia, Operação, RH, etc.). Cada child page descreve fluxos, artefatos (Strapi, Metabase, Zendesk, Mapa de mercado, Governança). Use `scripts/notion-export.sh <pageId>` ou `scripts/notion_export_recursive.py` para extrair markdown atualizado.
- **Notion / Base Einstein** (`95c2dfe4878...`): database com respostas padrão para dúvidas; consultar via `/v1/data_sources/{id}/query` e indexar os campos `Pergunta`, `Resposta`, `Tags`.
- **Notion / Transportadoras Parceiras** (`2ac5a2553557...`): tabela com SLAs, contatos e requisitos por transportadora; usar para perguntas sobre cobertura logística.
- **Zendesk público:** artigos oficiais (https://smartenvios.zendesk.com/hc/pt-br). Ideal para instruções passo a passo já liberadas para clientes.
- **Playlists YouTube:** 4 coleções oficiais (Onboarding Geral, Integrações, Funcionalidades Avançadas, Casos de Uso). Referencie vídeos com timestamp quando a pergunta exigir demonstração.
- **MCP Staging (`https://staging.smartenvios.tec.br/mcp`):** expõe endpoints para simular features e criar/atualizar OKRs/Jira/Zendesk via automação.
- **GitHub rafaelcanper:** código dos microserviços (`/var/www/ms.*`) + conectores; use READMEs para responder dúvidas técnicas e, se necessário, navegar para outros repositórios via `gh repo clone`.

---

## FAQ - Perguntas Frequentes

### Integração com Shopify

**Resposta:**
Sim, a SmartEnvios integra nativamente com Shopify através de app oficial disponível na Shopify App Store.

**Links úteis:**
- App Shopify: https://apps.shopify.com/smartenvios
- Tutorial YouTube: [consultar playlist Integrações]
- Zendesk: [buscar artigo "shopify"]

### Como rastrear um envio?

**Resposta:**
O rastreamento pode ser feito de 3 formas:
1. Painel SmartEnvios → aba "Envios"
2. Link de rastreamento enviado ao cliente por email/SMS
3. API de rastreamento (para integrações)

**Microserviço responsável:** `ms.expedition-hub`

### Webhooks não estão chegando

**Troubleshooting:**
1. Verificar URL configurada no painel
2. Testar URL com curl: `curl -X POST https://sua-url/webhook`
3. Checar logs no `ms.notifications`
4. Validar que servidor aceita HTTPS

**Repositório:** `/var/www/ms.notifications`

---

## Notion – Processos SmartEnvios

### Estrutura raiz (`Processos`, pageId `21f21016bd48807588b1f3e0e13f72c3`)
Cadência de rotinas por área. Sempre cite a área + subpágina para orientar humanos.

| Área | Subpáginas chave | Uso típico |
| --- | --- | --- |
| Marketing | Strapi (alertas e banners in-app), Sumário Metabase, Pesquisa de Mercado, Mapas de mercado/parceiros/stakeholders | Táticas de comunicação, dashboards e posicionamento |
| Comercial | Playbooks de pré-venda, roteiros, políticas de preço, materiais de apoio | Perguntas sobre processo comercial / habilitação de parceiros |
| Sucesso do Cliente | Onboarding, rituais com clientes, matrizes de saúde, scripts de QBR | Ajudar em dúvidas sobre relacionamento e cadências |
| Experiência Cliente | Jornadas, métricas NPS, planos de ação | Explicar como feedbacks são coletados e tratados |
| Tecnologia | Dados/Metabase, Zendesk integrações, Roteiros, Metodologia RICE, Segurança, Governança | Perguntas técnicas sobre produto, suporte e priorização |
| Financeiro | Fluxos de cobrança, conciliação, indicadores | Respostas sobre boletos, split e relatórios financeiros |
| Operação | SLAs internos, monitors, squads de operação | Questões sobre expedição, performance e rotinas diárias |
| Recursos Humanos | Trilhas, políticas, avaliação, onboarding interno | Perguntas sobre processos de pessoas |
| Franquias | Materiais e processos para unidades franqueadas | Explicar como franquias operam |
| Transportadoras | Base de parceiros logísticos (ver seção própria) | SLA, cobertura e requisitos |

> 💡 **Como usar:** ao responder, cite o bloco específico (ex.: “Processos → Tecnologia → Segurança da informação”) e resuma o procedimento. Para detalhes extensos, linke o pageId correspondente.

### Exportar/atualizar
- `./scripts/notion-export.sh <pageId> agents/einstein/knowledge/notion/<slug>.md` para dumps rápidos.
- `./scripts/notion_export_recursive.py` para capturar subpáginas (use com parcimônia; alto volume).
- Registrar a data da exportação no topo do arquivo.

---

## Notion – Base de Conhecimento Einstein

**Database:** `95c2dfe4878a4180a99f4a2c21ac0ea9`

Campos úteis:
- `Pergunta (title)` – texto da dúvida
- `Resposta (rich_text)` – resposta oficial
- `Tipo` – categoria (Produto, Financeiro, Operação...)
- `Tags` – filtros rápidos

Uso recomendado:
1. Rodar query filtrando por tags relacionadas à pergunta.
2. Se não houver resposta direta, complementar com Notion Processos + Zendesk e registrar nova FAQ no database.

---

## Transportadoras Parceiras

**Página:** `2ac5a2553557458e947f891bb639c4a0`

Conteúdo esperado:
- Lista de parceiros (Correios, Jadlog, Azul Cargo, Loggi, etc.)
- SLA padrão, peso/medidas máximos, regiões atendidas
- Documentos/contratos, passos para ativação
- Contatos de suporte e escalonamento

Responder perguntas sobre cobertura logística citando: transportadora + SLA + restrições (peso/CEP) e direcionar para onboarding se necessário.

---

## APIs e Integrações

### Principais Endpoints

**Rastreamento:**
```
GET /api/v1/rastreio/:codigo
```

**Criar Envio:**
```
POST /api/v1/envios
Body: {destinatario, pacote, ...}
```

**Webhooks:**
```
POST /api/v1/webhooks/configurar
Body: {url, eventos: [...]}
```

**Documentação completa:** MCP staging ou Zendesk

---

## Troubleshooting Comum

### Erro: "CEP inválido"

**Causa:** CEP fora do padrão ou não encontrado.

**Solução:**
1. Validar formato: `XXXXX-XXX` (8 dígitos)
2. Consultar em https://buscacepinter.correios.com.br
3. Se válido mas erro persiste, abrir ticket

**Repo relacionado:** `/var/www/ms.connectors` (validação de CEP)

### Integração não sincroniza pedidos

**Causa:** Credenciais inválidas ou permissões insuficientes.

**Solução:**
1. Revalidar credenciais no painel
2. Verificar permissões da API key
3. Testar endpoint manualmente
4. Consultar logs em `ms.connectors`

**Tutorial:** YouTube Playlist "Integrações" → vídeo sobre troubleshooting

---

## Changelog e Updates

(A ser populado com mudanças recentes da plataforma)

---

## 🛠️ Como Responder Dúvidas

### Template de Resposta Completa

1. **Resposta direta** (1-2 frases)
2. **Explicação** (contexto, como funciona)
3. **Links úteis** (Zendesk, YouTube, GitHub)
4. **Próximos passos** (se aplicável)

**Exemplo:**
> Sim, integramos com Shopify através do app oficial! 🎉
>
> A integração permite importar pedidos automaticamente, gerar etiquetas em lote, e enviar códigos de rastreamento de volta para a loja.
>
> **Setup:**
> - App Shopify: https://apps.shopify.com/smartenvios
> - Tutorial: [link YouTube]
> - Guia completo: [link Zendesk]
>
> Após instalar, você precisará conectar sua conta SmartEnvios. Alguma dúvida no processo?

---

## Ações Operacionais (OKR / Jira / Zendesk)

Quando a resposta exigir abrir tarefa/solicitação:

1. **OKR (Notion Tech DB)**
   - Usar MCP ou Notion API para inserir item no database de OKRs.
   - Campos mínimos: `Objetivo`, `Resultado-chave`, `Status`, `Owner (people)`, `Fonte da demanda`.
   - Referenciar sempre a conversa/solicitação original no campo de notas.

2. **Jira**
   - Acessar via helper local: `workspace/agents/einstein/scripts/jira-helper.sh`.
   - Padrão de título: `[Equipe] - Problema/Feature - Contexto breve`.
   - Descrição deve incluir: cenário atual, passo a passo para reproduzir, logs/print, prioridade sugerida.
   - Assignee: resolver por nome e cachear (`.pi/jira-assignees.json`) antes de pedir `accountId`.
   - Dropdowns: preencher `Produto`, `Projeto`, `Integracao`, `Categoria` conforme identidade da demanda.
   - Tipo: inferir por motivo (`Bug`/`Story`/`Task`).
   - Prioridade padrão: `Highest`; status alvo: `To Do` / `Tarefas pendentes`.
   - Regras detalhadas: `workspace/agents/einstein/knowledge/jira/classification-rules.md`.

3. **Zendesk**
   - Para solicitações externas, usar API/CLI para criar ticket com tag `Einstein`.
   - Campos obrigatórios: requester, assunto, descrição estruturada (## Impacto / ## Passos / ## Evidências).

4. **Checklist de resiliência**
   - Buscar IDs de usuários/projetos antes de alegar que “não encontrou”.
   - Validar se a integração está autorizada (tokens em `.env`) e registrar pendências somente após tentativa concreta.

Documentar no card/registro o que foi criado (link direto + referência) para permitir auditoria posterior.

---

## 📝 Enriquecimento Contínuo

**Sempre que responder uma dúvida:**
1. Adicione FAQ aqui se for recorrente
2. Documente troubleshooting novo
3. Atualize links/referências
4. Registre bugs conhecidos

**Fontes para monitorar:**
- Conversations no Discord
- Tickets recorrentes
- Updates no GitHub (repos SmartEnvios)
- Novos vídeos YouTube
- Artigos novos no Zendesk
