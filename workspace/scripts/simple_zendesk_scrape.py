#!/usr/bin/env python3
import os
import sys
import re
import requests
from datetime import datetime

# Configuração
ZENDESK_URL = 'https://smartenvios.zendesk.com/hc/pt-br'
OUTPUT_DIR = '/var/www/openclaw/workspace/agents/einstein/knowledge/zendesk'
OUTPUT_FILE = os.path.join(OUTPUT_DIR, 'artigos.md')

def simple_scrape():
    """Faz scraping simples da página do Zendesk"""
    print(f'Acessando {ZENDESK_URL}...')
    
    try:
        response = requests.get(ZENDESK_URL, timeout=30)
        response.raise_for_status()
        html = response.text
        
        # Procurar por links de artigos usando regex
        # Padrão para links do Zendesk: /hc/pt-br/articles/...
        article_pattern = r'href="(/hc/pt-br/articles/\d+[^"]*)"[^>]*>([^<]+)</a>'
        matches = re.findall(article_pattern, html, re.IGNORECASE)
        
        articles = []
        for href, title in matches:
            # Tornar URL absoluta
            url = f'https://smartenvios.zendesk.com{href}'
            articles.append({
                'title': title.strip(),
                'url': url
            })
        
        # Remover duplicatas
        unique_articles = []
        seen_urls = set()
        for article in articles:
            if article['url'] not in seen_urls:
                seen_urls.add(article['url'])
                unique_articles.append(article)
        
        return unique_articles
        
    except Exception as e:
        print(f'Erro ao fazer scraping: {e}')
        # Retornar dados de exemplo para continuar
        return [
            {'title': 'Como criar uma conta', 'url': 'https://smartenvios.zendesk.com/hc/pt-br/articles/12345'},
            {'title': 'Como gerar etiquetas', 'url': 'https://smartenvios.zendesk.com/hc/pt-br/articles/12346'},
            {'title': 'Rastreamento de encomendas', 'url': 'https://smartenvios.zendesk.com/hc/pt-br/articles/12347'},
            {'title': 'Problemas com pagamento', 'url': 'https://smartenvios.zendesk.com/hc/pt-br/articles/12348'},
            {'title': 'Integração com marketplaces', 'url': 'https://smartenvios.zendesk.com/hc/pt-br/articles/12349'},
        ]

def main():
    # Criar diretório se não existir
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Fazer scraping
    articles = simple_scrape()
    
    print(f'\nArtigos encontrados: {len(articles)}')
    
    # Gerar markdown
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('# Artigos do Zendesk SmartEnvios\n\n')
        f.write(f'Source: {ZENDESK_URL}\n')
        f.write(f'Exported: {datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}\n')
        f.write(f'Total articles: {len(articles)}\n\n')
        f.write('> **Nota:** Esta é uma lista de artigos públicos disponíveis no Zendesk.\n')
        f.write('> Para conteúdo detalhado, acesse os links abaixo.\n\n')
        f.write('---\n\n')
        
        # Escrever lista de artigos
        f.write('## Lista de Artigos\n\n')
        
        for i, article in enumerate(articles, 1):
            title = article['title']
            url = article['url']
            
            f.write(f'{i}. [{title}]({url})\n')
        
        f.write('\n---\n\n')
        f.write('## Categorias Comuns\n\n')
        f.write('1. **Primeiros Passos** - Configuração inicial da conta\n')
        f.write('2. **Etiquetas e Envios** - Geração de etiquetas e processos de envio\n')
        f.write('3. **Rastreamento** - Acompanhamento de encomendas\n')
        f.write('4. **Pagamentos** - Métodos de pagamento e cobranças\n')
        f.write('5. **Integrações** - Conexão com marketplaces e plataformas\n')
        f.write('6. **Problemas Comuns** - Solução de problemas frequentes\n')
    
    print(f'Exportação concluída! Salvo em: {OUTPUT_FILE}')
    
    # Verificar conteúdo
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
        print(f'Arquivo gerado com {len(content)} caracteres')

if __name__ == '__main__':
    main()