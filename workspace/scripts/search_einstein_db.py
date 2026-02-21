#!/usr/bin/env python3
import os
import sys
import requests

# Configuração
API_KEY = os.environ.get('NOTION_SMARTENVIOS_API_KEY')
if not API_KEY:
    print('Missing NOTION_SMARTENVIOS_API_KEY', file=sys.stderr)
    sys.exit(1)

BASE_URL = 'https://api.notion.com/v1'
HEADERS = {
    'Authorization': f'Bearer {API_KEY}',
    'Notion-Version': '2022-06-28'
}

def search_databases(query=""):
    """Busca bancos de dados"""
    url = f'{BASE_URL}/search'
    payload = {
        'filter': {'property': 'object', 'value': 'database'},
        'query': query
    }
    
    response = requests.post(url, headers=HEADERS, json=payload)
    response.raise_for_status()
    return response.json()

def main():
    print('Buscando bancos de dados no workspace SmartEnvios...')
    
    # Primeiro, buscar todos os bancos de dados
    results = search_databases()
    databases = results.get('results', [])
    
    print(f'Encontrados {len(databases)} bancos de dados\n')
    
    # Listar bancos de dados com nomes que possam conter "Einstein" ou "Base"
    for db in databases:
        db_id = db.get('id', 'N/A')
        title_parts = db.get('title', [])
        title = ''.join(part.get('plain_text', '') for part in title_parts)
        
        # Verificar propriedades também
        properties = db.get('properties', {})
        
        print(f'ID: {db_id}')
        print(f'Título: {title if title else "(sem título)"}')
        print(f'URL: https://notion.so/{db_id}')
        
        # Verificar se tem propriedades que parecem ser de FAQ/base de conhecimento
        possible_faq_props = []
        for prop_name, prop_info in properties.items():
            prop_type = prop_info.get('type', 'unknown')
            if prop_name.lower() in ['pergunta', 'resposta', 'question', 'answer', 'faq', 'tags', 'categoria']:
                possible_faq_props.append(f'{prop_name} ({prop_type})')
        
        if possible_faq_props:
            print(f'Possível base de conhecimento: {", ".join(possible_faq_props)}')
        
        print('---\n')
    
    # Agora buscar especificamente por "Einstein"
    print('\n=== BUSCA POR "EINSTEIN" ===')
    einstein_results = search_databases("Einstein")
    einstein_dbs = einstein_results.get('results', [])
    
    if einstein_dbs:
        print(f'Encontrados {len(einstein_dbs)} bancos com "Einstein" no título')
        for db in einstein_dbs:
            db_id = db.get('id', 'N/A')
            title_parts = db.get('title', [])
            title = ''.join(part.get('plain_text', '') for part in title_parts)
            print(f'  - {title}: {db_id}')
    else:
        print('Nenhum banco encontrado com "Einstein" no título')
    
    # Buscar por "Base"
    print('\n=== BUSCA POR "BASE" ===')
    base_results = search_databases("Base")
    base_dbs = base_results.get('results', [])
    
    if base_dbs:
        print(f'Encontrados {len(base_dbs)} bancos com "Base" no título')
        for db in base_dbs:
            db_id = db.get('id', 'N/A')
            title_parts = db.get('title', [])
            title = ''.join(part.get('plain_text', '') for part in title_parts)
            print(f'  - {title}: {db_id}')

if __name__ == '__main__':
    main()