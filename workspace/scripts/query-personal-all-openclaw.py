#!/usr/bin/env python3
import json
import os
import sys
import requests

# Carregar API key
api_key = os.getenv('NOTION_PERSONAL_API_KEY')
if not api_key:
    print('{"error": "API key NOTION_PERSONAL_API_KEY not found"}')
    sys.exit(1)

# ID do banco de dados pessoal
db_id = 'bfcbe7a7a3a745489e605e0762af12a9'

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

# Consultar TODOS os cards com Tipo OpenClaw
filter_data = {
    'filter': {
        'property': 'Tipo',
        'select': {'equals': 'OpenClaw'}
    }
}

try:
    response = requests.post(
        f'https://api.notion.com/v1/databases/{db_id}/query',
        headers=headers,
        json=filter_data
    )
    response.raise_for_status()
    
    data = response.json()
    results = data.get('results', [])
    
    # Organizar por status
    cards_by_status = {
        'Aguardando': [],
        'Priorizado': [],
        'Em andamento': [],
        'Concluído': [],
        'Impedimento': [],
        'Anotações': [],
        'Outro': []
    }
    
    for card in results:
        props = card.get('properties', {})
        name = props.get('Name', {}).get('title', [{}])[0].get('text', {}).get('content', 'Sem título')
        status = props.get('Status', {}).get('select', {}).get('name', 'Sem status')
        tipo = props.get('Tipo', {}).get('select', {}).get('name', '')
        agente = props.get('Agente', {}).get('select', {}).get('name', '')
        
        card_info = {
            'id': card.get('id'),
            'name': name,
            'status': status,
            'tipo': tipo,
            'agente': agente,
            'url': card.get('url', '')
        }
        
        if status in cards_by_status:
            cards_by_status[status].append(card_info)
        else:
            cards_by_status['Outro'].append(card_info)
    
    # Contar totais
    totals = {status: len(cards) for status, cards in cards_by_status.items()}
    
    print(json.dumps({
        'totals': totals,
        'cards_by_status': cards_by_status
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')