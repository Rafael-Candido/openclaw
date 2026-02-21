#!/usr/bin/env python3
import json
import os
import sys
import requests
from datetime import datetime, timezone

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

# Consultar cards em Priorizado
filter_data = {
    'filter': {
        'and': [
            {'property': 'Status', 'select': {'equals': 'Priorizado'}},
            {'property': 'Tipo', 'select': {'equals': 'OpenClaw'}}
        ]
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
    
    now = datetime.now(timezone.utc)
    stalled_cards = []
    
    for card in results:
        props = card.get('properties', {})
        name = props.get('Name', {}).get('title', [{}])[0].get('text', {}).get('content', 'Sem título')
        agente = props.get('Agente', {}).get('select', {}).get('name', '')
        
        # Verificar data de criação
        created_time = card.get('created_time', '')
        if created_time:
            created_dt = datetime.fromisoformat(created_time.replace('Z', '+00:00'))
            age_hours = (now - created_dt).total_seconds() / 3600
            
            # Considerar travado se > 4 horas em Priorizado
            if age_hours > 4:
                stalled_cards.append({
                    'id': card.get('id'),
                    'name': name,
                    'agente': agente,
                    'created_time': created_time,
                    'age_hours': round(age_hours, 1),
                    'url': card.get('url', '')
                })
    
    print(json.dumps({
        'total_priorizado': len(results),
        'stalled_count': len(stalled_cards),
        'stalled_cards': stalled_cards
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')