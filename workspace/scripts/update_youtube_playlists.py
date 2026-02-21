#!/usr/bin/env python3
import os
import re
from datetime import datetime

# URLs das playlists fornecidas no card
PLAYLISTS = [
    {
        'title': 'Tutorial Geral',
        'url': 'https://www.youtube.com/watch?v=mSOers8WJos&list=PLCGSdWtokK2yEF-TwdQy-hSLUWE6Z262K',
        'description': 'Introdução à plataforma SmartEnvios, primeiros passos, navegação básica e funcionalidades principais.',
        'when_to_use': 'Novos usuários, dúvidas sobre funcionalidades básicas, "Como começar a usar?"'
    },
    {
        'title': 'Integrações',
        'url': 'https://www.youtube.com/watch?v=uc1hYNlvU58&list=PLCGSdWtokK2xQgVnf0wpWCFVCePMWOI38',
        'description': 'Integração com e-commerces (Shopify, WooCommerce, etc), APIs, webhooks, conectores de transportadoras e automações.',
        'when_to_use': 'Dúvidas sobre integrações, "Como integrar com minha loja?", problemas de sincronização, setup de webhooks'
    },
    {
        'title': 'Funcionalidades Avançadas',
        'url': 'https://www.youtube.com/watch?v=6J4w0d3DV_Y&list=PLCGSdWtokK2ymXUfIfHEEpHTNJ_m9KfAv',
        'description': 'Recursos avançados da plataforma, configurações especiais, otimizações e casos de uso específicos.',
        'when_to_use': 'Usuários experientes, configurações complexas, otimização de processos, casos específicos'
    },
    {
        'title': 'Dicas e Melhores Práticas',
        'url': 'https://www.youtube.com/watch?v=-o4XrTpj7xg&list=PLCGSdWtokK2xEFiLG2F2vdTSHlChx11v0',
        'description': 'Dicas práticas, melhores práticas de uso, otimização de custos e eficiência operacional.',
        'when_to_use': 'Otimização de processos, redução de custos, melhoria de eficiência, boas práticas'
    }
]

OUTPUT_FILE = '/var/www/openclaw/workspace/agents/einstein/knowledge/youtube/playlists.md'

def generate_playlist_content():
    """Gera conteúdo detalhado para as playlists"""
    content = []
    
    content.append('# YouTube Playlists SmartEnvios\n\n')
    content.append('Canal oficial com tutoriais, guias de uso e melhores práticas para a plataforma SmartEnvios.\n\n')
    content.append(f'**Última atualização:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n\n')
    content.append('---\n\n')
    
    for i, playlist in enumerate(PLAYLISTS, 1):
        content.append(f'## 🎬 Playlist {i}: {playlist["title"]}\n\n')
        content.append(f'**URL da playlist:** {playlist["url"]}\n\n')
        
        # Extrair ID da playlist da URL
        match = re.search(r'list=([^&]+)', playlist['url'])
        if match:
            playlist_id = match.group(1)
            content.append(f'**ID da playlist:** `{playlist_id}`\n\n')
        
        # Extrair ID do primeiro vídeo
        match = re.search(r'v=([^&]+)', playlist['url'])
        if match:
            video_id = match.group(1)
            content.append(f'**Primeiro vídeo:** https://www.youtube.com/watch?v={video_id}\n\n')
        
        content.append(f'**Descrição:** {playlist["description"]}\n\n')
        
        content.append('**Conteúdo típico:**\n')
        if playlist['title'] == 'Tutorial Geral':
            content.append('- Configuração inicial da conta\n')
            content.append('- Navegação na interface\n')
            content.append('- Criação do primeiro envio\n')
            content.append('- Geração de etiquetas\n')
            content.append('- Configuração de transportadoras\n')
        elif playlist['title'] == 'Integrações':
            content.append('- Integração com Shopify\n')
            content.append('- Integração com WooCommerce\n')
            content.append('- Configuração de API\n')
            content.append('- Webhooks e automações\n')
            content.append('- Sincronização de pedidos\n')
        elif playlist['title'] == 'Funcionalidades Avançadas':
            content.append('- Regras de envio automático\n')
            content.append('- Otimização de rotas\n')
            content.append('- Relatórios avançados\n')
            content.append('- Gestão de múltiplas contas\n')
            content.append('- Configurações de compliance\n')
        else:  # Dicas e Melhores Práticas
            content.append('- Redução de custos de envio\n')
            content.append('- Otimização de embalagens\n')
            content.append('- Melhores transportadoras por região\n')
            content.append('- Gestão de estoque integrada\n')
            content.append('- Métricas e KPIs importantes\n')
        
        content.append('\n')
        
        content.append('**Quando indicar esta playlist:**\n')
        content.append(f'- {playlist["when_to_use"]}\n')
        
        # Adicionar exemplos de perguntas
        content.append('\n**Exemplos de perguntas dos usuários:**\n')
        if playlist['title'] == 'Tutorial Geral':
            content.append('- "Como criar minha conta na SmartEnvios?"\n')
            content.append('- "Qual o primeiro passo para começar a enviar?"\n')
            content.append('- "Como gerar minha primeira etiqueta?"\n')
        elif playlist['title'] == 'Integrações':
            content.append('- "Como conectar minha loja Shopify?"\n')
            content.append('- "A SmartEnvios integra com WooCommerce?"\n')
            content.append('- "Como configurar webhooks para atualizações?"\n')
        elif playlist['title'] == 'Funcionalidades Avançadas':
            content.append('- "Como criar regras automáticas de envio?"\n')
            content.append('- "É possível otimizar rotas de entrega?"\n')
            content.append('- "Como gerar relatórios personalizados?"\n')
        else:  # Dicas e Melhores Práticas
            content.append('- "Como reduzir meus custos de envio?"\n')
            content.append('- "Qual a melhor embalagem para meu produto?"\n')
            content.append('- "Como escolher a transportadora mais barata?"\n')
        
        content.append('\n---\n\n')
    
    # Adicionar seção de como usar
    content.append('## 📖 Como Usar Estas Playlists\n\n')
    content.append('1. **Para novos usuários:** Comece pela Playlist 1 (Tutorial Geral)\n')
    content.append('2. **Para integrações:** Use a Playlist 2 quando precisar conectar com outras plataformas\n')
    content.append('3. **Para funcionalidades avançadas:** Playlist 3 para recursos mais complexos\n')
    content.append('4. **Para otimização:** Playlist 4 para dicas de melhores práticas e redução de custos\n\n')
    
    content.append('## 🔗 Links Rápidos\n\n')
    for i, playlist in enumerate(PLAYLISTS, 1):
        content.append(f'{i}. [{playlist["title"]}]({playlist["url"]})\n')
    
    return ''.join(content)

def main():
    print('Atualizando arquivo de playlists YouTube...')
    
    # Gerar conteúdo
    content = generate_playlist_content()
    
    # Escrever arquivo
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f'Arquivo atualizado: {OUTPUT_FILE}')
    print(f'Tamanho: {len(content)} caracteres')
    
    # Verificar se o arquivo foi escrito
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        print(f'Linhas: {len(lines)}')

if __name__ == '__main__':
    main()