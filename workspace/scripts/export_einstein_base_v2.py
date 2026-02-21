#!/usr/bin/env python3
import os
import sys
import json
import requests
from datetime import datetime

# Configuração
API_KEY = os.environ.get('NOTION_SMARTENVIOS_API_KEY')
if not API_KEY:
    print('Missing NOTION_SMARTENVIOS_API_KEY', file=sys.stderr)
    sys.exit(1)

DATABASE_ID = '95c2dfe4878a4180a99f4a2c21ac0ea9'
OUTPUT_FILE = '/var/www/openclaw/workspace/agents/einstein/knowledge/notion/base-conhecimento.md'

BASE_URL = 'https://api.notion.com/v1'
HEADERS = {
    'Authorization': f'Bearer {API_KEY}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

def fetch_database_pages():
    """Busca todas as páginas do banco de dados"""
    all_pages = []
    has_more = True
    next_cursor = None
    
    while has_more:
        url = f'{BASE_URL}/databases/{DATABASE_ID}/query'
        payload = {}
        if next_cursor:
            payload['start_cursor'] = next_cursor
        
        response = requests.post(url, headers=HEADERS, json=payload)
        response.raise_for_status()
        data = response.json()
        
        all_pages.extend(data.get('results', []))
        has_more = data.get('has_more', False)
        next_cursor = data.get('next_cursor')
    
    return all_pages

def extract_property(page, prop_name, prop_type='title'):
    """Extrai valor de uma propriedade da página"""
    prop = page.get('properties', {}).get(prop_name)
    if not prop:
        return '' if prop_type != 'multi_select' else []
    
    if prop_type == 'title':
        title_parts = prop.get('title', [])
        return ''.join(part.get('plain_text', '') for part in title_parts)
    elif prop_type == 'rich_text':
        rich_text_parts = prop.get('rich_text', [])
        return ''.join(part.get('plain_text', '') for part in rich_text_parts)
    elif prop_type == 'multi_select':
        select_items = prop.get('multi_select', [])
        return [item.get('name', '') for item in select_items]
    elif prop_type == 'select':
        select_item = prop.get('select')
        return select_item.get('name', '') if select_item else ''
    elif prop_type == 'date':
        date_info = prop.get('date')
        return date_info.get('start', '') if date_info else ''
    else:
        return ''

def main():
    print(f'Exportando Base Einstein (database_id: {DATABASE_ID})...')
    
    # Buscar páginas
    pages = fetch_database_pages()
    print(f'Encontradas {len(pages)} entradas na base de conhecimento')
    
    # Contadores para debug
    with_question = 0
    with_answer = 0
    with_both = 0
    
    # Gerar markdown
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('# Base de Conhecimento Einstein\n\n')
        f.write(f'Source: https://notion.so/{DATABASE_ID}\n')
        f.write(f'Exported: {datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}\n')
        f.write(f'Total entries in database: {len(pages)}\n\n')
        f.write('---\n\n')
        
        for i, page in enumerate(pages, 1):
            # Extrair propriedades
            pergunta = extract_property(page, 'Pergunta', 'title')
            resposta = extract_property(page, 'Resposta', 'rich_text')
            tags = extract_property(page, 'Tags', 'multi_select')
            categoria = extract_property(page, 'Categoria', 'select')
            status = extract_property(page, 'Status', 'select')
            created = extract_property(page, 'Date Created', 'date')
            
            # Debug counters
            if pergunta:
                with_question += 1
            if resposta:
                with_answer += 1
            if pergunta and resposta:
                with_both += 1
            
            # Incluir mesmo se não tiver resposta completa
            if not pergunta:
                pergunta = f'Entry {i} (no question)'
            
            f.write(f'## {i}. {pergunta}\n\n')
            
            if categoria:
                f.write(f'**Categoria:** {categoria}  \n')
            if tags:
                f.write(f'**Tags:** {", ".join(tags)}  \n')
            if status:
                f.write(f'**Status:** {status}  \n')
            if created:
                f.write(f'**Criado em:** {created}  \n')
            
            if resposta:
                f.write('\n**Resposta:**\n\n')
                f.write(f'{resposta}\n\n')
            else:
                f.write('\n**Resposta:** *(sem conteúdo)*\n\n')
            
            f.write('---\n\n')
    
    print(f'Debug: Com pergunta: {with_question}, Com resposta: {with_answer}, Com ambos: {with_both}')
    print(f'Exportação concluída! Salvo em: {OUTPUT_FILE}')

if __name__ == '__main__':
    main()