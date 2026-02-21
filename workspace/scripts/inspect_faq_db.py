#!/usr/bin/env python3
import os
import sys
import json
import requests

# Configuração
API_KEY = os.environ.get('NOTION_SMARTENVIOS_API_KEY')
if not API_KEY:
    print('Missing NOTION_SMARTENVIOS_API_KEY', file=sys.stderr)
    sys.exit(1)

DATABASE_ID = '1f64d30b-d485-4221-8f9c-709a50aada86'

BASE_URL = 'https://api.notion.com/v1'
HEADERS = {
    'Authorization': f'Bearer {API_KEY}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

def fetch_database():
    """Busca informações do banco de dados"""
    url = f'{BASE_URL}/databases/{DATABASE_ID}'
    response = requests.get(url, headers=HEADERS)
    response.raise_for_status()
    return response.json()

def fetch_sample_pages():
    """Busca algumas páginas de exemplo"""
    url = f'{BASE_URL}/databases/{DATABASE_ID}/query'
    payload = {'page_size': 10}
    response = requests.post(url, headers=HEADERS, json=payload)
    response.raise_for_status()
    return response.json()

def main():
    print(f'Inspecionando banco de dados F.A.Q: {DATABASE_ID}')
    
    # Buscar informações do banco
    db_info = fetch_database()
    
    print('\n=== PROPRIEDADES DO BANCO DE DADOS ===')
    properties = db_info.get('properties', {})
    for prop_name, prop_info in properties.items():
        prop_type = prop_info.get('type', 'unknown')
        print(f'{prop_name}: {prop_type}')
    
    # Buscar algumas páginas de exemplo
    print('\n=== PÁGINAS DE EXEMPLO (primeiras 10) ===')
    sample_data = fetch_sample_pages()
    pages = sample_data.get('results', [])
    
    print(f'Total de páginas encontradas: {len(pages)}')
    
    for i, page in enumerate(pages, 1):
        print(f'\n--- Página {i} ---')
        page_id = page.get('id', 'N/A')
        
        # Verificar propriedades
        properties = page.get('properties', {})
        
        # Extrair título
        title_prop = properties.get('Name') or properties.get('title') or next(iter(properties.values()))
        title = ''
        if title_prop.get('type') == 'title':
            title_parts = title_prop.get('title', [])
            title = ''.join(part.get('plain_text', '') for part in title_parts)
        
        print(f'Título: {title}')
        
        # Listar todas as propriedades
        for prop_name, prop_info in properties.items():
            prop_type = prop_info.get('type', 'unknown')
            
            # Extrair valor baseado no tipo
            if prop_type == 'title':
                title_parts = prop_info.get('title', [])
                value = ''.join(part.get('plain_text', '') for part in title_parts)
                if value:
                    print(f'  {prop_name} ({prop_type}): "{value}"')
            elif prop_type == 'rich_text':
                rich_text_parts = prop_info.get('rich_text', [])
                value = ''.join(part.get('plain_text', '') for part in rich_text_parts)
                if value:
                    print(f'  {prop_name} ({prop_type}): "{value[:100]}..."')
            elif prop_type == 'select':
                select_item = prop_info.get('select')
                value = select_item.get('name', '') if select_item else ''
                if value:
                    print(f'  {prop_name} ({prop_type}): "{value}"')
            elif prop_type == 'multi_select':
                select_items = prop_info.get('multi_select', [])
                values = [item.get('name', '') for item in select_items]
                if values:
                    print(f'  {prop_name} ({prop_type}): {values}')

if __name__ == '__main__':
    main()