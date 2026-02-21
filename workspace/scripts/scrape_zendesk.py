#!/usr/bin/env python3
import os
import sys
import requests
from datetime import datetime
from bs4 import BeautifulSoup

# Configuração
ZENDESK_URL = 'https://smartenvios.zendesk.com/hc/pt-br'
OUTPUT_DIR = '/var/www/openclaw/workspace/agents/einstein/knowledge/zendesk'
OUTPUT_FILE = os.path.join(OUTPUT_DIR, 'artigos.md')

def scrape_zendesk():
    """Faz scraping da página do Zendesk para extrair artigos"""
    print(f'Acessando {ZENDESK_URL}...')
    
    try:
        response = requests.get(ZENDESK_URL, timeout=30)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Encontrar seções/categorias
        sections = soup.find_all('section', class_='section')
        
        articles_data = []
        
        for section in sections:
            # Tentar encontrar título da seção
            section_title_elem = section.find('h2') or section.find('h3') or section.find(['a', 'span'])
            section_title = section_title_elem.get_text(strip=True) if section_title_elem else 'Seção sem título'
            
            # Encontrar artigos na seção
            article_links = section.find_all('a', href=True)
            
            for link in article_links:
                href = link['href']
                title = link.get_text(strip=True)
                
                # Filtrar apenas links de artigos (que contêm /articles/)
                if '/articles/' in href and title:
                    # Tornar URL absoluta se for relativa
                    if href.startswith('/'):
                        href = f'https://smartenvios.zendesk.com{href}'
                    elif not href.startswith('http'):
                        href = f'{ZENDESK_URL}/{href}'
                    
                    articles_data.append({
                        'title': title,
                        'url': href,
                        'section': section_title
                    })
        
        return articles_data
        
    except Exception as e:
        print(f'Erro ao fazer scraping: {e}')
        return []

def main():
    # Criar diretório se não existir
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Fazer scraping
    articles = scrape_zendesk()
    
    print(f'\nArtigos encontrados: {len(articles)}')
    
    # Gerar markdown
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('# Artigos do Zendesk SmartEnvios\n\n')
        f.write(f'Source: {ZENDESK_URL}\n')
        f.write(f'Exported: {datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}\n')
        f.write(f'Total articles: {len(articles)}\n\n')
        f.write('---\n\n')
        
        # Organizar por seção
        sections = {}
        for article in articles:
            section = article['section']
            if section not in sections:
                sections[section] = []
            sections[section].append(article)
        
        # Escrever por seção
        for section_title, section_articles in sections.items():
            f.write(f'## {section_title}\n\n')
            
            for i, article in enumerate(section_articles, 1):
                title = article['title']
                url = article['url']
                
                f.write(f'{i}. [{title}]({url})\n')
            
            f.write('\n---\n\n')
    
    print(f'Exportação concluída! Salvo em: {OUTPUT_FILE}')
    
    # Verificar conteúdo do arquivo
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        print(f'Arquivo gerado com {len(lines)} linhas')

if __name__ == '__main__':
    main()