#!/usr/bin/env python3
import os
import shutil
from datetime import datetime

# Caminhos
KNOWLEDGE_FILE = '/var/www/openclaw/workspace/agents/einstein/KNOWLEDGE.md'
BACKUP_FILE = KNOWLEDGE_FILE + '.backup_' + datetime.now().strftime('%Y%m%d_%H%M%S')

def create_consolidated_knowledge():
    """Cria uma versão consolidada do KNOWLEDGE.md"""
    
    content = []
    
    # Cabeçalho
    content.append('# KNOWLEDGE.md - Base de Conhecimento SmartEnvios (Consolidada)\n\n')
    content.append(f'> **Última consolidação:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n\n')
    content.append('## 📋 Sumário Executivo\n\n')
    content.append('Esta base integra múltiplas fontes de informação para responder dúvidas sobre a plataforma SmartEnvios:\n\n')
    content.append('1. **Notion** - Processos internos e base de conhecimento\n')
    content.append('2. **Zendesk** - Artigos públicos de suporte\n')
    content.append('3. **YouTube** - Playlists de tutoriais\n')
    content.append('4. **GitHub** - Repositórios de microserviços\n')
    content.append('5. **MCP** - API para automações\n\n')
    
    content.append('---\n\n')
    
    # Seção 1: Fontes de Informação
    content.append('## 📚 Fontes de Informação\n\n')
    content.append('### 1. Notion SmartEnvios\n\n')
    content.append('**Workspace principal:** Processos internos e documentação\n\n')
    content.append('**Bancos de dados principais:**\n')
    content.append('- **Processos** (`21f21016bd48807588b1f3e0e13f72c3`): Árvore completa de rotinas por área\n')
    content.append('- **Base de Conhecimento** (`95c2dfe4878a4180a99f4a2c21ac0ea9`): FAQ interna (246 entradas)\n')
    content.append('- **Transportadoras Parceiras** (`2ac5a2553557458e947f891bb639c4a0`): SLAs e requisitos\n')
    content.append('- **F.A.Q** (`1f64d30b-d485-4221-8f9c-709a50aada86`): Categorias de artigos\n\n')
    
    content.append('**Como acessar:**\n')
    content.append('- API Notion com chave `NOTION_SMARTENVIOS_API_KEY`\n')
    content.append('- Scripts: `notion-export.sh`, `notion_export_recursive.py`\n')
    content.append('- Exportar para: `agents/einstein/knowledge/notion/`\n\n')
    
    content.append('### 2. Zendesk Público\n\n')
    content.append('**URL:** https://smartenvios.zendesk.com/hc/pt-br\n\n')
    content.append('**Conteúdo:** Artigos oficiais de suporte para clientes\n\n')
    content.append('**Status atual:** Scraping automático não funcionou (possível bloqueio)\n')
    content.append('**Alternativa:** Referenciar URL diretamente ou usar busca manual\n\n')
    
    content.append('### 3. YouTube - Playlists Oficiais\n\n')
    content.append('**Canal:** SmartEnvios (tutoriais e guias)\n\n')
    content.append('**Playlists disponíveis (4):**\n')
    content.append('1. **Tutorial Geral** - Introdução e primeiros passos\n')
    content.append('2. **Integrações** - Conexão com e-commerces e APIs\n')
    content.append('3. **Funcionalidades Avançadas** - Recursos complexos\n')
    content.append('4. **Dicas e Melhores Práticas** - Otimização e eficiência\n\n')
    
    content.append('**Arquivo local:** `agents/einstein/knowledge/youtube/playlists.md`\n\n')
    
    content.append('### 4. GitHub - Repositórios Locais\n\n')
    content.append('**Localização:** `/var/www/ms.*` (10 microserviços)\n\n')
    content.append('**Inventário completo:** `agents/einstein/knowledge/github/local-repos.md`\n\n')
    content.append('**Microserviços principais:**\n')
    content.append('- `ms.atendimento` - Sistema de atendimento\n')
    content.append('- `ms.connectors` - Conectores e integrações\n')
    content.append('- `ms.crm` - CRM interno\n')
    content.append('- `ms.customer-service` - Serviço ao cliente\n')
    content.append('- `ms.expedition-hub` - Hub de expedição\n')
    content.append('- `ms.label-processor` - Processador de etiquetas\n')
    content.append('- `ms.notifications` - Sistema de notificações\n')
    content.append('- `ms.points` - Sistema de pontos\n')
    content.append('- `ms.ticket-generator` - Gerador de tickets\n')
    content.append('- `ms.zardbank` - Integração financeira\n\n')
    
    content.append('**Tecnologias predominantes:** Node.js, TypeScript, NestJS, Docker\n\n')
    
    content.append('### 5. MCP SmartEnvios\n\n')
    content.append('**URL staging:** https://staging.smartenvios.tec.br/mcp\n\n')
    content.append('**Funcionalidades:**\n')
    content.append('- Consulta de CEP\n')
    content.append('- Criação/atualização de OKRs\n')
    content.append('- Integração com Jira\n')
    content.append('- Automação de tickets Zendesk\n\n')
    
    content.append('**Script:** `scripts/smartenvios-mcp.sh`\n\n')
    
    content.append('---\n\n')
    
    # Seção 2: Fluxos de Trabalho
    content.append('## 🔄 Fluxos de Trabalho Recomendados\n\n')
    
    content.append('### Para dúvidas gerais de usuários:\n')
    content.append('1. Verificar Base Einstein (Notion) por pergunta similar\n')
    content.append('2. Buscar em Zendesk por artigos relacionados\n')
    content.append('3. Recomendar playlist YouTube apropriada\n')
    content.append('4. Se não encontrar, pesquisar em Processos Notion\n\n')
    
    content.append('### Para dúvidas técnicas/bugs:\n')
    content.append('1. Identificar microserviço relacionado no GitHub\n')
    content.append('2. Verificar README e documentação do repositório\n')
    content.append('3. Consultar logs ou configurações típicas\n')
    content.append('4. Sugerir troubleshooting baseado em código\n\n')
    
    content.append('### Para integrações:\n')
    content.append('1. Playlist YouTube "Integrações"\n')
    content.append('2. Código fonte em `ms.connectors`\n')
    content.append('3. Artigos Zendesk de setup\n')
    content.append('4. Testar via MCP se aplicável\n\n')
    
    content.append('---\n\n')
    
    # Seção 3: FAQ Consolidada
    content.append('## ❓ FAQ Consolidada - Perguntas Mais Frequentes\n\n')
    
    content.append('### Integração com Shopify\n')
    content.append('**Resposta:** Sim, através do app oficial na Shopify App Store.\n\n')
    content.append('**Links:**\n')
    content.append('- App: https://apps.shopify.com/smartenvios\n')
    content.append('- Playlist: Integrações (vídeo específico)\n')
    content.append('- Microserviço: `ms.connectors`\n\n')
    
    content.append('### Como rastrear um envio?\n')
    content.append('**Resposta:** Painel SmartEnvios → aba "Envios" ou link de rastreamento enviado.\n\n')
    content.append('**Microserviço:** `ms.expedition-hub`\n\n')
    
    content.append('### Webhooks não funcionam\n')
    content.append('**Troubleshooting:**\n')
    content.append('1. Verificar URL configurada\n')
    content.append('2. Testar com curl\n')
    content.append('3. Checar logs em `ms.notifications`\n')
    content.append('4. Validar HTTPS\n\n')
    
    content.append('### CEP inválido\n')
    content.append('**Causa:** Formato incorreto ou não encontrado.\n\n')
    content.append('**Solução:**\n')
    content.append('1. Validar formato: `XXXXX-XXX`\n')
    content.append('2. Consultar Correios\n')
    content.append('3. Microserviço: `ms.connectors`\n\n')
    
    content.append('---\n\n')
    
    # Seção 4: Estrutura de Diretórios
    content.append('## 📁 Estrutura de Diretórios do Einstein\n\n')
    content.append('```\n')
    content.append('agents/einstein/knowledge/\n')
    content.append('├── notion/\n')
    content.append('│   ├── base-conhecimento.md      # Base Einstein (FAQ)\n')
    content.append('│   ├── processos.md              # Processos SmartEnvios\n')
    content.append('│   └── transportadoras.md        # Parceiros logísticos\n')
    content.append('├── youtube/\n')
    content.append('│   └── playlists.md              # 4 playlists oficiais\n')
    content.append('├── github/\n')
    content.append('│   ├── local-repos.md            # Inventário ms.*\n')
    content.append('│   └── local-repos.json          # JSON com detalhes\n')
    content.append('├── zendesk/\n')
    content.append('│   ├── artigos.md                # Lista de artigos\n')
    content.append('│   └── indice.md                 # Índice resumido\n')
    content.append('├── jira/\n')
    content.append('│   └── classification-rules.md   # Regras de classificação\n')
    content.append('└── mcp/\n')
    content.append('    └── (documentação MCP)\n')
    content.append('```\n\n')
    
    content.append('---\n\n')
    
    # Seção 5: Scripts Disponíveis
    content.append('## 🛠️ Scripts de Apoio\n\n')
    content.append('**Localização:** `/var/www/openclaw/workspace/scripts/`\n\n')
    content.append('| Script | Função | Uso |\n')
    content.append('|--------|--------|-----|\n')
    content.append('| `notion-export.sh` | Exportar página Notion | `./notion-export.sh <pageId> <output>` |\n')
    content.append('| `notion_export_recursive.py` | Exportar recursivo | `python3 notion_export_recursive.py <pageId> <output>` |\n')
    content.append('| `notion-helper.sh` | Helper para API | Consultar AGENTS.md |\n')
    content.append('| `smartenvios-mcp.sh` | Cliente MCP | `./smartenvios-mcp.sh login/call/tools` |\n')
    content.append('| `inventory_github_repos.py` | Inventário GitHub | `python3 inventory_github_repos.py` |\n')
    content.append('| `update_youtube_playlists.py` | Atualizar playlists | `python3 update_youtube_playlists.py` |\n')
    content.append('| `export_einstein_base.py` | Exportar Base Einstein | `python3 export_einstein_base.py` |\n')
    content.append('| `simple_zendesk_scrape.py` | Scraping Zendesk | `python3 simple_zendesk_scrape.py` |\n')
    content.append('\n')
    
    content.append('---\n\n')
    
    # Seção 6: Template de Resposta
    content.append('## 📝 Template de Resposta (Best Practice)\n\n')
    content.append('```markdown\n')
    content.append('✅ [Resposta direta e afirmativa]\n\n')
    content.append('📋 [Explicação detalhada em 2-3 frases]\n\n')
    content.append('🔗 **Links úteis:**\n')
    content.append('- [Título do recurso](URL)\n')
    content.append('- [Outro recurso](URL)\n\n')
    content.append('🛠️ **Se precisar de ajuda técnica:**\n')
    content.append('- Microserviço relacionado: `ms.nome-do-servico`\n')
    content.append('- Script para testar: `nome-do-script.sh`\n')
    content.append('```\n\n')
    
    content.append('---\n\n')
    
    # Seção 7: Status Atual
    content.append('## 📊 Status Atual da Base\n\n')
    content.append('| Fonte | Status | Última Atualização | Notas |\n')
    content.append('|-------|--------|-------------------|-------|\n')
    content.append('| Notion Processos | ⚠️ Parcial | 2026-02-20 | Exportação manual necessária |\n')
    content.append('| Base Einstein | ⚠️ Parcial | 2026-02-20 | 246 entradas, schema a verificar |\n')
    content.append('| YouTube Playlists | ✅ Completo | 2026-02-21 | 4 playlists detalhadas |\n')
    content.append('| GitHub Repos | ✅ Completo | 2026-02-21 | 10 microserviços inventariados |\n')
    content.append('| Zendesk | ⚠️ Limitado | 2026-02-21 | Scraping bloqueado, URLs apenas |\n')
    content.append('| MCP | ✅ Configurado | 2026-02-20 | Script funcionando |\n')
    content.append('\n')
    
    content.append('---\n\n')
    
    # Seção 8: Próximos Passos
    content.append('## 🎯 Próximos Passos Recomendados\n\n')
    content.append('1. **Exportar Processos Notion** recursivamente para markdown\n')
    content.append('2. **Resolver schema Base Einstein** para extrair perguntas/respostas\n')
    content.append('3. **Implementar scraping Zendesk** alternativo (API ou manual)\n')
    content.append('4. **Atualizar FAQ** com novas perguntas frequentes\n')
    content.append('5. **Integrar MCP** em respostas automáticas quando aplicável\n')
    content.append('6. **Monitorar atualizações** nos repositórios GitHub\n\n')
    
    content.append('---\n\n')
    
    content.append('*Documentação mantida pelo Engenheiro de Prompt - Varredura automática*\n')
    
    return ''.join(content)

def main():
    print('Consolidando KNOWLEDGE.md...')
    
    # Fazer backup do arquivo atual
    if os.path.exists(KNOWLEDGE_FILE):
        shutil.copy2(KNOWLEDGE_FILE, BACKUP_FILE)
        print(f'Backup criado: {BACKUP_FILE}')
    
    # Gerar conteúdo consolidado
    consolidated_content = create_consolidated_knowledge()
    
    # Escrever novo arquivo
    with open(KNOWLEDGE_FILE, 'w', encoding='utf-8') as f:
        f.write(consolidated_content)
    
    print(f'KNOWLEDGE.md consolidada e atualizada')
    print(f'Tamanho: {len(consolidated_content)} caracteres')
    
    # Verificar diferenças
    print('\n📈 Resumo da consolidação:')
    print('- ✅ Fontes de informação organizadas por tipo')
    print('- ✅ Fluxos de trabalho recomendados')
    print('- ✅ FAQ consolidada com respostas principais')
    print('- ✅ Estrutura de diretórios documentada')
    print('- ✅ Scripts de apoio listados')
    print('- ✅ Template de resposta padronizado')
    print('- ✅ Status atual de cada fonte')
    print('- ✅ Próximos passos identificados')

if __name__ == '__main__':
    main()