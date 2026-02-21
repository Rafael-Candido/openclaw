#!/usr/bin/env python3
import os
import sys
import json
import requests
from datetime import datetime

# Configuração
ZENDESK_BASE_URL = 'https://smartenvios.zendesk.com'
API_URL = f'{ZENDESK_BASE_URL}/hc/api/v2/help_center/pt-br/articles.json'
OUTPUT_DIR = '/var/www/openclaw/workspace/agents/einstein/knowledge/zendesk'
OUTPUT_FILE = os.path.join(OUTPUT_DIR, 'artigos.md')

def fetch_zendesk_articles():
    """Busca artigos públicos do Zendesk"""
    all_articles = []
    page_url = API_URL
    
    print('Buscando artigos do Zendesk...')
    
    while page_url:
        try:
            response = requests.get(page_url, timeout=30)
            response.raise_for_status()
            data = response.json()
            
            articles = data.get('articles', [])
            all_articles.extend(articles)
            
            print(f'  Página: {len(articles)} artigos')
            
            # Verificar próxima página
            page_url = data.get('next_page')
            
        except Exception as e:
            print(f'Erro ao buscar artigos: {e}')
            break
    
    return all_articles

def main():
    # Criar diretório se não existir
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Buscar artigos
    articles = fetch_zendesk_articles()
    
    print(f'\nTotal de artigos encontrados: {len(articles)}')
    
    # Organizar por categoria
    categories = {}
    for article in articles:
        category_id = article.get('section_id')
        if category_id not in categories:
            categories[category_id] = []
        categories[category_id].append(article)
    
    # Gerar markdown
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('# Artigos do Zendesk SmartEnvios\n\n')
        f.write(f'Source: {ZENDESK_BASE_URL}/hc/pt-br\n')
        f.write(f'Exported: {datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}\n')
        f.write(f'Total articles: {len(articles)}\n\n')
        f.write('---\n\n')
        
        # Para cada categoria
        for category_id, cat_articles in categories.items():
            f.write(f'## Categoria ID: {category_id}\n\n')
            
            for i, article in enumerate(cat_articles, 1):
                article_id = article.get('id', 'N/A')
                title = article.get('title', 'Sem título')
                url = article.get('html_url', '')
                created = article.get('created_at', '')
                updated = article.get('edited_at', '') or article.get('updated_at', '')
                vote_sum = article.get('vote_sum', 0)
                vote_count = article.get('vote_count', 0)
                
                f.write(f'### {i}. {title}\n\n')
                f.write(f'**ID:** {article_id}  \n')
                f.write(f'**URL:** {url}  \n')
                if created:
                    f.write(f'**Criado em:** {created}  \n')
                if updated:
                    f.write(f'**Atualizado em:** {updated}  \n')
                if vote_count > 0:
                    f.write(f'**Votos:** {vote_sum} ({vote_count} votos)  \n')
                
                # Extrair corpo (limitar tamanho)
                body = article.get('body', '')
                if len(body) > 1000:
                    body = body[:1000] + '...'
                
                f.write('\n**Conteúdo:**\n\n')
                f.write(f'{body}\n\n')
                f.write('---\n\n')
    
    print(f'Exportação concluída! Salvo em: {OUTPUT_FILE}')
    
    # Também criar um arquivo de índice resumido
    index_file = os.path.join(OUTPUT_DIR, 'indice.md')
    with open(index_file, 'w', encoding='utf-8') as f:
        f.write('# Índice de Artigos Zendesk\n\n')
        f.write(f'Total: {len(articles)} artigos\n\n')
        
        for article in articles[:50]:  # Limitar a 50 no índice
            title = article.get('title', 'Sem título')
            url = article.get('html_url', '')
            f.write(f'- [{title}]({url})\n')
        
        if len(articles) > 50:
            f.write(f'\n... e mais {len(articles) - 50} artigos\n')
    
    print(f'Índice criado: {index_file}')

if __name__ == '__main__':
    main()