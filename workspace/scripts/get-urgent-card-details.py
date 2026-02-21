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

# ID do card URGENTE
card_id = "30d36384-585c-81c2-adf0-f9ad4e6ba1da"

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

try:
    # Obter detalhes do card
    response = requests.get(
        f'https://api.notion.com/v1/pages/{card_id}',
        headers=headers
    )
    response.raise_for_status()
    
    card = response.json()
    
    # Obter blocos (conteúdo)
    blocks_response = requests.get(
        f'https://api.notion.com/v1/blocks/{card_id}/children',
        headers=headers
    )
    blocks_response.raise_for_status()
    
    blocks = blocks_response.json()
    
    # Extrair informações
    props = card.get('properties', {})
    name = props.get('Name', {}).get('title', [{}])[0].get('text', {}).get('content', 'Sem título')
    status = props.get('Status', {}).get('select', {}).get('name', '')
    tipo = props.get('Tipo', {}).get('select', {}).get('name', '')
    agente = props.get('Agente', {}).get('select', {}).get('name', '')
    
    # Extrair conteúdo dos blocos
    content = []
    for block in blocks.get('results', []):
        block_type = block.get('type')
        if block_type == 'paragraph':
            text = block.get('paragraph', {}).get('rich_text', [{}])[0].get('text', {}).get('content', '')
            if text:
                content.append(text)
        elif block_type == 'to_do':
            text = block.get('to_do', {}).get('rich_text', [{}])[0].get('text', {}).get('content', '')
            checked = block.get('to_do', {}).get('checked', False)
            if text:
                content.append(f"[{'✓' if checked else '☐'}] {text}")
        elif block_type == 'bulleted_list_item':
            text = block.get('bulleted_list_item', {}).get('rich_text', [{}])[0].get('text', {}).get('content', '')
            if text:
                content.append(f"• {text}")
    
    print(json.dumps({
        'card': {
            'id': card_id,
            'name': name,
            'status': status,
            'tipo': tipo,
            'agente': agente,
            'url': card.get('url', ''),
            'created_time': card.get('created_time', '')
        },
        'content': content,
        'content_count': len(content)
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')